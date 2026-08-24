fn main() {
    println!("cargo:rerun-if-env-changed=BEDROCK_INSTALLER_TRUST_CERT");
    println!("cargo:rerun-if-env-changed=BEDROCK_REQUIRE_PRODUCTION_TRUST");
    println!("cargo:rerun-if-env-changed=BEDROCK_APPLE_TEAM_ID");
    println!("cargo:rerun-if-env-changed=BEDROCK_ENABLE_PHYSICAL_WRITER");
    println!("cargo:rustc-check-cfg=cfg(bedrock_physical_writer)");
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS is set");

    if let Some(value) = std::env::var_os("BEDROCK_ENABLE_PHYSICAL_WRITER") {
        if value != "I_ACCEPT_REAL_DEVICE_DATA_LOSS" {
            panic!("BEDROCK_ENABLE_PHYSICAL_WRITER has an invalid value");
        }
        if std::env::var_os("BEDROCK_REQUIRE_PRODUCTION_TRUST").is_none() {
            panic!("physical writer builds require BEDROCK_REQUIRE_PRODUCTION_TRUST");
        }
        if target_os != "linux" {
            panic!("the gated physical writer is not connected on this target OS");
        }
        println!("cargo:rustc-cfg=bedrock_physical_writer");
    }

    if target_os == "macos" {
        println!("cargo:rerun-if-changed=src/macos_service.m");
        cc::Build::new()
            .file("src/macos_service.m")
            .flag("-fobjc-arc")
            .flag("-fblocks")
            .flag("-mmacosx-version-min=13.0")
            .compile("bedrock_macos_service");
        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=framework=ServiceManagement");
        if std::env::var_os("BEDROCK_REQUIRE_PRODUCTION_TRUST").is_some() {
            let team_id = std::env::var("BEDROCK_APPLE_TEAM_ID")
                .expect("production macOS installer builds require BEDROCK_APPLE_TEAM_ID");
            if team_id.len() != 10
                || !team_id
                    .bytes()
                    .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
            {
                panic!("BEDROCK_APPLE_TEAM_ID must be ten uppercase letters or digits");
            }
        }
    }

    let out_dir = std::path::PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR is set"));
    let embedded_cert = out_dir.join("bedrock-release-trust.pem");
    match std::env::var_os("BEDROCK_INSTALLER_TRUST_CERT") {
        Some(source) => {
            let certificate = std::fs::read(&source)
                .expect("BEDROCK_INSTALLER_TRUST_CERT must point to a readable public certificate");
            if !certificate.starts_with(b"-----BEGIN CERTIFICATE-----") {
                panic!("BEDROCK_INSTALLER_TRUST_CERT must contain a PEM certificate");
            }
            std::fs::write(&embedded_cert, certificate)
                .expect("could not prepare the embedded public release certificate");
        }
        None if std::env::var_os("BEDROCK_REQUIRE_PRODUCTION_TRUST").is_some() => {
            panic!("production installer builds require BEDROCK_INSTALLER_TRUST_CERT");
        }
        None => {
            std::fs::write(&embedded_cert, [])
                .expect("could not create the fail-closed development trust placeholder");
        }
    }

    tauri_build::build()
}
