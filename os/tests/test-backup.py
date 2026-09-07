#!/usr/bin/python3
import hashlib, json, os, pathlib, subprocess, sys, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]; TOOL=ROOT/"os/config/includes.chroot/usr/sbin/bedrock-backup"
def invoke(env,*args,ok=True):
    result=subprocess.run([sys.executable,str(TOOL),*args],env=env,capture_output=True,text=True)
    if ok and result.returncode: raise AssertionError(result.stderr)
    return result

def main():
    with tempfile.TemporaryDirectory() as temporary:
        work=pathlib.Path(temporary); state=work/"state"; data=work/"data"; repos=work/"repos"; restores=data/"restores"
        for path in (state/"secrets",data/"share",repos): path.mkdir(parents=True)
        (data/"share/file.txt").write_text("important data")
        password=state/"secrets/nightly.password"; password.write_text("a-long-test-password"); password.chmod(0o600)
        log=work/"restic.log"; stub=work/"restic.py"
        stub.write_text('''#!/usr/bin/python3
import json,os,pathlib,sys
with open(os.environ["BEDROCK_TEST_RESTIC_LOG"],"a") as out: out.write(" ".join(sys.argv[1:])+"|secret="+str(bool(os.environ.get("RESTIC_PASSWORD_FILE")))+"\\n")
if "snapshots" in sys.argv: print(json.dumps([{"id":"0123456789abcdef0123456789abcdef"}]))
if "init" in sys.argv: pathlib.Path(sys.argv[sys.argv.index("-r")+1]).mkdir(parents=True)
if "restore" in sys.argv: pathlib.Path(sys.argv[sys.argv.index("--target")+1]).mkdir(parents=True)
'''); stub.chmod(0o755)
        env=os.environ|{"BEDROCK_BACKUP_TEST_MODE":"1","BEDROCK_BACKUP_STATE_DIR":str(state),"BEDROCK_BACKUP_DATA_ROOT":str(data),"BEDROCK_BACKUP_LOCAL_ROOT":str(repos),"BEDROCK_BACKUP_RESTORE_ROOT":str(restores),"BEDROCK_BACKUP_RESTIC":str(stub),"BEDROCK_BACKUP_TEST_NOW":"172800","BEDROCK_TEST_RESTIC_LOG":str(log)}
        request={"id":"nightly","name":"Nightly files","source":str(data/"share"),"repository":str(repos/"nightly"),"kind":"local","schedule":{"frequency":"daily","hour_utc":0,"weekday":None},"retention":{"daily":7,"weekly":4,"monthly":6},"initialize":True}
        request_path=work/"request.json"; request_path.write_text(json.dumps(request))
        digest=hashlib.sha256(json.dumps(request,sort_keys=True,separators=(",",":")).encode()).hexdigest(); confirmation=f"CREATE ENCRYPTED BACKUP nightly {digest}"
        assert invoke(env,"create",str(request_path),"wrong",ok=False).returncode
        invoke(env,"create",str(request_path),confirmation)
        listing=json.loads(invoke(env,"list").stdout); assert listing["plans"][0]["retention"]["monthly"]==6 and "password" not in json.dumps(listing)
        status=json.loads((state/"status.json").read_text()); assert status["plans"][0]["id"]=="nightly" and "source" not in json.dumps(status) and "repository" not in json.dumps(status) and "last_snapshot" not in json.dumps(status)
        result=json.loads(invoke(env,"run","nightly","RUN ENCRYPTED BACKUP nightly").stdout); snapshot=result["snapshot"]
        assert json.loads((state/"status.json").read_text())["plans"][0]["has_snapshot"] is True
        commands=log.read_text(); assert " backup " in commands and "forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6" in commands and "secret=True" in commands and "a-long-test-password" not in commands
        assert invoke(env,"restore","nightly",snapshot,"wrong",ok=False).returncode and not (restores/"nightly").exists()
        invoke(env,"restore","nightly",snapshot,f"RESTORE BACKUP nightly SNAPSHOT {snapshot}"); assert (restores/"nightly").is_dir()
        pathlib.Path(restores/"nightly").rmdir(); before=log.read_text().count(" backup "); env["BEDROCK_BACKUP_TEST_NOW"]="259200"; invoke(env,"run-due"); assert log.read_text().count(" backup ")==before+1
    print("Bedrock encrypted backup plan, retention, schedule, and restore tests passed.")
if __name__=="__main__": main()
