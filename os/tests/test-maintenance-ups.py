#!/usr/bin/python3
import json,os,pathlib,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]; MAINT=ROOT/"os/config/includes.chroot/usr/sbin/bedrock-maintenance"; UPS=ROOT/"os/config/includes.chroot/usr/lib/bedrock/handle-ups-event"; GUARD=ROOT/"os/config/includes.chroot/usr/lib/bedrock/require-normal-mode"
def invoke(tool,env,*args,ok=True):
    result=subprocess.run([sys.executable,str(tool),*args],env=env,capture_output=True,text=True)
    if ok and result.returncode: raise AssertionError(result.stderr)
    return result
def main():
    guarded=["clone-vm","control-vm","convert-vm-image","create-passthrough-plan","create-vm","create-vm-plan","delete-vm","import-vm-image","import-vm-image-archive","manage-isolated-network","manage-vm-image-attachment","manage-vm-network-attachment","manage-vm-passthrough","manage-vm-snapshot","register-vm","render-vm-domain","update-vm-resources"]
    for name in guarded: assert "/usr/lib/bedrock/require-normal-mode" in (ROOT/"os/config/includes.chroot/usr/lib/bedrock"/name).read_text()
    for name in ["bedrock-apps","bedrock-nas","bedrock-storage","bedrock-storage-guided","bedrock-update","bedrock-update-settings"]: assert "/usr/lib/bedrock/require-normal-mode" in (ROOT/"os/config/includes.chroot/usr/sbin"/name).read_text()
    policy=(ROOT/"os/config/includes.chroot/etc/nut/upssched.conf").read_text(); assert "AT LOWBATT * EXECUTE LOWBATT" in policy and "AT FSD * EXECUTE FSD" in policy
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
elif "shutdown" in args:
    if os.environ.get("BEDROCK_TEST_VM_STUCK")!="1": state.write_text("off")
    open(os.environ["BEDROCK_TEST_OPERATION_LOG"],"a").write("virsh shutdown media-vm\\n")
elif "domstate" in args: print("shut off" if state.read_text()=="off" else "running")
''')
        podman=work/"podman.py"; podman.write_text('''import os,sys
args=sys.argv[1:]
if args and args[0]=="ps": print("bedrock-app-photos")
else: open(os.environ["BEDROCK_TEST_OPERATION_LOG"],"a").write("podman "+" ".join(args)+"\\n")
''')
        env=os.environ|{"BEDROCK_MAINTENANCE_TEST_MODE":"1","BEDROCK_MAINTENANCE_STATE_DIR":str(state),"BEDROCK_MAINTENANCE_SYSTEMCTL":str(systemctl),"BEDROCK_MAINTENANCE_VIRSH":str(virsh),"BEDROCK_MAINTENANCE_PODMAN":str(podman),"BEDROCK_MAINTENANCE_DOMAINS":str(domains),"BEDROCK_MAINTENANCE_TEST_NOW":"1000","BEDROCK_TEST_OPERATION_LOG":str(log),"BEDROCK_TEST_VM_STATE":str(runtime)}
        assert invoke(MAINT,env,"enter","wrong",ok=False).returncode
        active=json.loads(invoke(MAINT,env,"enter","ENTER BEDROCK MAINTENANCE").stdout); assert active["mode"]=="active" and active["vms"]==["media-vm"]
        operations=log.read_text(); assert "virsh shutdown media-vm" in operations and "podman stop --time 30 bedrock-app-photos" in operations and "systemctl stop smbd.service" in operations and "systemctl stop bedrock-backup.timer" in operations
        guard_env=env|{"BEDROCK_MAINTENANCE_GUARD_TEST_MODE":"1","BEDROCK_MAINTENANCE_GUARD_STATE":str(state/"state.json")}; assert invoke(GUARD,guard_env,ok=False).returncode
        assert invoke(MAINT,env,"exit","wrong",ok=False).returncode
        assert json.loads(invoke(MAINT,env,"exit","EXIT BEDROCK MAINTENANCE").stdout)["mode"]=="inactive" and invoke(GUARD,guard_env).returncode==0 and "podman start bedrock-app-photos" in log.read_text()
        runtime.write_text("running"); stuck=env|{"BEDROCK_TEST_VM_STUCK":"1"}; assert invoke(MAINT,stuck,"enter","ENTER BEDROCK MAINTENANCE",ok=False).returncode
        assert json.loads(invoke(MAINT,env,"status").stdout)["mode"]=="failed" and invoke(GUARD,guard_env,ok=False).returncode
        invoke(MAINT,env,"exit","EXIT BEDROCK MAINTENANCE")
        runtime.write_text("running"); ups_state=work/"ups.json"; ups_env=env|{"BEDROCK_UPS_TEST_MODE":"1","BEDROCK_UPS_STATE":str(ups_state),"BEDROCK_UPS_MAINTENANCE":str(MAINT),"BEDROCK_UPS_SYSTEMCTL":str(systemctl),"BEDROCK_UPS_TEST_NOW":"1100"}
        low=json.loads(invoke(UPS,ups_env,"LOWBATT").stdout); assert low["maintenance_quiesced"] is True and low["shutdown_requested"] is True and "systemctl poweroff --no-block" in log.read_text()
        assert invoke(UPS,ups_env,"UNKNOWN",ok=False).returncode
    print("Bedrock maintenance quiesce, mutation guard, and UPS shutdown tests passed.")
if __name__=="__main__": main()
