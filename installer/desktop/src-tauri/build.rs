fn main() {
    println!("cargo:rerun-if-env-changed=BEDROCK_INSTALLER_TRUST_CERT");
    println!("cargo:rerun-if-env-changed=BEDROCK_REQUIRE_PRODUCTION_TRUST");
    println!("cargo:rerun-if-env-changed=BEDROCK_APPLE_TEAM_ID");

    let target_os = std::env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS is set");
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
