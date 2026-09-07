#!/usr/bin/python3
import json,os,pathlib,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]; MAINT=ROOT/"os/config/includes.chroot/usr/sbin/bedrock-maintenance"; UPS=ROOT/"os/config/includes.chroot/usr/lib/bedrock/handle-ups-event"; GUARD=ROOT/"os/config/includes.chroot/usr/lib/bedrock/require-normal-mode"
def invoke(tool,env,*args,ok=True):
    result=subprocess.run([sys.executable,str(tool),*args],env=env,capture_output=True,text=True)
    if ok and result.returncode: raise AssertionError(result.stderr)
    return result
def main():
    with tempfile.TemporaryDirectory() as temporary:
        work=pathlib.Path(temporary); state=work/"maintenance"; runtime=work/"vm-state"; runtime.write_text("running"); log=work/"operations.log"; domains=work/"domains.json"; domains.write_text(json.dumps({"schema":1,"domains":[{"name":"media-vm","vcpus":2,"memory_mib":2048}]}))
        systemctl=work/"systemctl.py"; systemctl.write_text('''import os,sys
args=sys.argv[1:]
if args[:2]==["is-active","--quiet"]: raise SystemExit(0 if args[2] in {"bedrock-backup.timer","smbd.service"} else 3)
with open(os.environ["BEDROCK_TEST_OPERATION_LOG"],"a") as out: out.write("systemctl "+" ".join(args)+"\\n")
''')
        virsh=work/"virsh.py"; virsh.write_text('''import os,pathlib,sys
args=sys.argv[1:]; state=pathlib.Path(os.environ["BEDROCK_TEST_VM_STATE"])
if "list" in args: print("media-vm" if state.read_text()=="running" else "")
elif "shutdown" in args: state.write_text("off"); open(os.environ["BEDROCK_TEST_OPERATION_LOG"],"a").write("virsh shutdown media-vm\\n")
elif "domstate" in args: print("shut off" if state.read_text()=="off" else "running")
''')
        env=os.environ|{"BEDROCK_MAINTENANCE_TEST_MODE":"1","BEDROCK_MAINTENANCE_STATE_DIR":str(state),"BEDROCK_MAINTENANCE_SYSTEMCTL":str(systemctl),"BEDROCK_MAINTENANCE_VIRSH":str(virsh),"BEDROCK_MAINTENANCE_DOMAINS":str(domains),"BEDROCK_MAINTENANCE_TEST_NOW":"1000","BEDROCK_TEST_OPERATION_LOG":str(log),"BEDROCK_TEST_VM_STATE":str(runtime)}
        assert invoke(MAINT,env,"enter","wrong",ok=False).returncode
        active=json.loads(invoke(MAINT,env,"enter","ENTER BEDROCK MAINTENANCE").stdout); assert active["mode"]=="active" and active["vms"]==["media-vm"]
        operations=log.read_text(); assert "virsh shutdown media-vm" in operations and "systemctl stop smbd.service" in operations and "systemctl stop bedrock-backup.timer" in operations
        guard_env=env|{"BEDROCK_MAINTENANCE_GUARD_TEST_MODE":"1","BEDROCK_MAINTENANCE_GUARD_STATE":str(state/"state.json")}; assert invoke(GUARD,guard_env,ok=False).returncode
        assert invoke(MAINT,env,"exit","wrong",ok=False).returncode
        assert json.loads(invoke(MAINT,env,"exit","EXIT BEDROCK MAINTENANCE").stdout)["mode"]=="inactive" and invoke(GUARD,guard_env).returncode==0
        runtime.write_text("running"); ups_state=work/"ups.json"; ups_env=env|{"BEDROCK_UPS_TEST_MODE":"1","BEDROCK_UPS_STATE":str(ups_state),"BEDROCK_UPS_MAINTENANCE":str(MAINT),"BEDROCK_UPS_SYSTEMCTL":str(systemctl),"BEDROCK_UPS_TEST_NOW":"1100"}
        low=json.loads(invoke(UPS,ups_env,"LOWBATT").stdout); assert low["maintenance_quiesced"] is True and low["shutdown_requested"] is True and "systemctl poweroff --no-block" in log.read_text()
        assert invoke(UPS,ups_env,"UNKNOWN",ok=False).returncode
    print("Bedrock maintenance quiesce, mutation guard, and UPS shutdown tests passed.")
if __name__=="__main__": main()
