#!/usr/bin/python3
import hashlib,json,os,pathlib,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]; TOOL=ROOT/"os/config/includes.chroot/usr/sbin/bedrock-apps"
def call(env,*args,ok=True):
    result=subprocess.run([sys.executable,str(TOOL),*args],env=env,text=True,capture_output=True)
    if ok and result.returncode: raise AssertionError(result.stderr)
    return result
def request(path,digest="sha256:"+"a"*64,policy="notify",network="bridge",ports=None):
    value={"id":"photos","name":"Photos","image":"registry.example/bedrock/photos:stable","digest":digest,"network":network,"ports":[{"host":8443,"container":8080,"protocol":"tcp"}] if ports is None else ports,"resources":{"cpus":1.5,"memory_mib":512,"pids":128},"update_policy":policy}; path.write_text(json.dumps(value)); return value
def confirm(action,value): return f"{action} APPLICATION {value['id']} "+hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":")).encode()).hexdigest()
def main():
    with tempfile.TemporaryDirectory() as temporary:
        work=pathlib.Path(temporary); state=work/"state"; data=work/"data"; log=work/"runtime.log"; podman=work/"podman.py"; skopeo=work/"skopeo.py"
        podman.write_text('import os,pathlib,sys\na=sys.argv[1:]; s=pathlib.Path(os.environ["BEDROCK_TEST_APP_RUNNING"]); open(os.environ["BEDROCK_TEST_APP_LOG"],"a").write("podman "+" ".join(a)+"\\n")\nif a and a[0]=="start": s.write_text("true")\nif a and a[0] in {"stop","rm"}: s.write_text("false")\nif a and a[0]=="inspect": print(s.read_text() if s.exists() else "false")\n'); skopeo.write_text('print("sha256:"+"b"*64)\n')
        env=os.environ|{"BEDROCK_APPS_TEST_MODE":"1","BEDROCK_APPS_STATE_DIR":str(state),"BEDROCK_APPS_DATA_DIR":str(data),"BEDROCK_APPS_PODMAN":str(podman),"BEDROCK_APPS_SKOPEO":str(skopeo),"BEDROCK_APPS_TEST_NOW":"1000","BEDROCK_TEST_APP_LOG":str(log),"BEDROCK_TEST_APP_RUNNING":str(work/"running")}; path=work/"request.json"; value=request(path)
        assert call(env,"install",str(path),"wrong",ok=False).returncode
        result=json.loads(call(env,"install",str(path),confirm("INSTALL",value)).stdout); assert result["status"]=="installed"
        status=json.loads((state/"status.json").read_text()); assert status["apps"][0]["id"]=="photos" and status["apps"][0]["running"] is True and "image" not in json.dumps(status) and "digest" not in json.dumps(status)
        commands=log.read_text(); assert "--read-only" in commands and "--cap-drop=all" in commands and "--security-opt=no-new-privileges" in commands and "--user 65532:65532" in commands and "--memory 512m" in commands and "--cpus 1.5" in commands and "--pids-limit 128" in commands and "--network bridge" in commands and "8443:8080/tcp" in commands and "@sha256:" in commands
        assert (data/"photos").is_dir() and len(json.loads(call(env,"list").stdout)["apps"])==1
        updates=json.loads(call(env,"check-updates").stdout); assert updates["updates"][0]=={"id":"photos","status":"available"} and json.loads((state/"status.json").read_text())["apps"][0]["update_available"] is True
        assert call(env,"update-latest","photos","wrong",ok=False).returncode; call(env,"update-latest","photos","UPDATE APPLICATION photos"); assert json.loads(call(env,"list").stdout)["apps"][0]["digest"].endswith("b"*64) and json.loads((state/"status.json").read_text())["apps"][0]["update_available"] is False
        bad=request(path,network="none",ports=[{"host":8443,"container":8080,"protocol":"tcp"}]); assert call(env,"update",str(path),confirm("UPDATE",bad),ok=False).returncode
        call(env,"stop","photos","STOP APPLICATION photos"); assert json.loads((state/"status.json").read_text())["apps"][0]["running"] is False
        call(env,"start","photos","START APPLICATION photos"); assert json.loads((state/"status.json").read_text())["apps"][0]["running"] is True
        assert call(env,"remove","photos","wrong",ok=False).returncode; call(env,"remove","photos","REMOVE APPLICATION photos")
        staged=request(path); assert call(env,"stage-install",str(path),"wrong",ok=False).returncode; call(env,"stage-install",str(path),confirm("STAGE",staged))
        safe=json.loads((state/"status.json").read_text()); assert safe["apps"]==[] and safe["install_candidates"][0]["id"]=="photos" and "image" not in json.dumps(safe) and "digest" not in json.dumps(safe)
        assert call(env,"install-staged","photos","wrong",ok=False).returncode; call(env,"install-staged","photos","INSTALL APPLICATION photos"); assert json.loads((state/"status.json").read_text())["install_candidates"]==[]
        call(env,"remove","photos","REMOVE APPLICATION photos")
        assert json.loads(call(env,"list").stdout)["apps"]==[] and (data/"photos").is_dir()
        assert json.loads((state/"status.json").read_text())["apps"]==[] and json.loads((state/"status.json").read_text())["install_candidates"]==[]
    print("Bedrock isolated application lifecycle, limits, and update-policy tests passed.")
if __name__=="__main__": main()
