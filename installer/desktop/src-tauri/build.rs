fn main() {
    println!("cargo:rerun-if-env-changed=BEDROCK_INSTALLER_TRUST_CERT");
    println!("cargo:rerun-if-env-changed=BEDROCK_REQUIRE_PRODUCTION_TRUST");

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
