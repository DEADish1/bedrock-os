#!/usr/bin/python3
import json, os, pathlib, subprocess, sys, tarfile, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]; TOOL=ROOT/"os/config/includes.chroot/usr/sbin/bedrock-config-backup"
def run(env,*args,ok=True):
    result=subprocess.run([sys.executable,str(TOOL),*args],env=env,capture_output=True,text=True)
    if ok and result.returncode: raise AssertionError(result.stderr)
    return result
def main():
    with tempfile.TemporaryDirectory() as temporary:
        work=pathlib.Path(temporary); source=work/"source"; restored=work/"restored"; source.mkdir(); restored.mkdir()
        for root in (source,restored):
            (root/"etc").mkdir(); (root/"etc/bedrock-release").write_text("BEDROCK_VERSION=0.2.0-dev\n")
            (root/"var/lib/bedrock/settings").mkdir(parents=True)
        policy={"schema":2,"channel":"stable"}; (source/"var/lib/bedrock/settings/update-policy.json").write_text(json.dumps(policy))
        (source/"var/lib/bedrock/api").mkdir(); (source/"var/lib/bedrock/api/tokens.json").write_text('{"secret":"never"}')
        archive=work/"config.tar.gz"; env=os.environ|{"BEDROCK_CONFIG_BACKUP_TEST_MODE":"1","BEDROCK_CONFIG_BACKUP_ROOT":str(source),"BEDROCK_CONFIG_BACKUP_TEST_NOW":"1000"}
        assert run(env,"export","wrong",str(archive),ok=False).returncode and not archive.exists()
        run(env,"export","EXPORT BEDROCK CONFIGURATION",str(archive))
        with tarfile.open(archive,"r:gz") as bundle:
            assert "configuration/settings/update-policy.json" in bundle.getnames()
            assert "tokens.json" not in " ".join(bundle.getnames())
        target=restored/"var/lib/bedrock/settings/update-policy.json"; target.write_text('{"old":true}')
        restore_env=env|{"BEDROCK_CONFIG_BACKUP_ROOT":str(restored)}
        assert run(restore_env,"restore","wrong",str(archive),ok=False).returncode and json.loads(target.read_text())=={"old":True}
        (restored/"etc/bedrock-release").write_text("BEDROCK_VERSION=0.3.0-dev\n")
        assert run(restore_env,"restore","RESTORE BEDROCK CONFIGURATION",str(archive),ok=False).returncode and json.loads(target.read_text())=={"old":True}
        (restored/"etc/bedrock-release").write_text("BEDROCK_VERSION=0.2.0-dev\n")
        result=run(restore_env,"restore","RESTORE BEDROCK CONFIGURATION",str(archive)); body=json.loads(result.stdout)
        assert body["reboot_required"] is True and json.loads(target.read_text())==policy
        recovery=pathlib.Path(body["recovery"]); assert json.loads((recovery/"settings/update-policy.json").read_text())=={"old":True}
    print("Bedrock configuration export/import tests passed.")
if __name__=="__main__": main()
