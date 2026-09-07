#!/usr/bin/python3
import hashlib,json,os,pathlib,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]; TOOL=ROOT/"os/config/includes.chroot/usr/sbin/bedrock-notifications"
def invoke(env,*args,ok=True):
    result=subprocess.run([sys.executable,str(TOOL),*args],env=env,capture_output=True,text=True)
    if ok and result.returncode: raise AssertionError(result.stderr)
    return result
def configure(env,work,request):
    path=work/(request["id"]+".json"); path.write_text(json.dumps(request)); digest=hashlib.sha256(json.dumps(request,sort_keys=True,separators=(",",":")).encode()).hexdigest()
    invoke(env,"configure",str(path),f"CONFIGURE NOTIFICATION {request['id']} {digest}")
def main():
    with tempfile.TemporaryDirectory() as temporary:
        work=pathlib.Path(temporary); state=work/"state"; secrets=state/"secrets"; secrets.mkdir(parents=True); alerts=work/"alerts.json"; log=work/"transport.jsonl"; helper=work/"transport.py"
        helper.write_text('''import os,sys
body=sys.stdin.read()
if os.environ.get("BEDROCK_TEST_NOTIFICATION_FAIL_KIND")==sys.argv[1]: raise SystemExit(1)
with open(os.environ["BEDROCK_TEST_NOTIFICATION_LOG"],"a") as out: out.write(body+"\\n")
''')
        (secrets/"phone.token").write_text("long-webhook-token"); (secrets/"phone.token").chmod(0o600)
        (secrets/"admin-email.json").write_text(json.dumps({"username":"admin","password":"long-email-password"})); (secrets/"admin-email.json").chmod(0o600)
        env=os.environ|{"BEDROCK_NOTIFICATIONS_TEST_MODE":"1","BEDROCK_NOTIFICATIONS_STATE_DIR":str(state),"BEDROCK_NOTIFICATIONS_ALERTS":str(alerts),"BEDROCK_NOTIFICATIONS_TEST_TRANSPORT":str(helper),"BEDROCK_NOTIFICATIONS_TEST_NOW":"1000","BEDROCK_TEST_NOTIFICATION_LOG":str(log)}
        configure(env,work,{"id":"phone","name":"Phone webhook","kind":"webhook","endpoint":"https://notify.example.test/bedrock"})
        configure(env,work,{"id":"admin-email","name":"Administrator email","kind":"email","smtp_host":"smtp.example.test","smtp_port":465,"sender":"bedrock@example.test","recipient":"admin@example.test"})
        listing=invoke(env,"list").stdout; assert "long-webhook-token" not in listing and "long-email-password" not in listing
        alerts.write_text(json.dumps({"schema":1,"events":[{"event_id":"opened:disk-smart:/dev/private:1000","action":"opened","alert_id":"disk-smart:/dev/private","kind":"disk-smart","resource":"/dev/private","severity":"critical","previous_severity":None,"occurred_unix":1000},{"event_id":"resolved:disk-smart:/dev/private:1100","action":"resolved","alert_id":"disk-smart:/dev/private","kind":"disk-smart","resource":"/dev/private","severity":"critical","previous_severity":"critical","occurred_unix":1100}]}))
        assert json.loads(invoke(env,"dispatch").stdout)["delivered"]==4
        records=[json.loads(line) for line in log.read_text().splitlines()]; assert len(records)==4
        combined=json.dumps(records); assert "/dev/private" not in combined and "opened:disk-smart" not in combined and "replace-disk" in combined
        assert json.loads(invoke(env,"dispatch").stdout)["delivered"]==0 and len(log.read_text().splitlines())==4
        value=json.loads(alerts.read_text()); value["events"].append({"event_id":"severity:disk-temperature:/dev/private:1200","action":"severity-changed","alert_id":"disk-temperature:/dev/private","kind":"disk-temperature","resource":"/dev/private","severity":"critical","previous_severity":"warning","occurred_unix":1200}); alerts.write_text(json.dumps(value))
        failed_env=env|{"BEDROCK_TEST_NOTIFICATION_FAIL_KIND":"webhook"}; assert invoke(failed_env,"dispatch",ok=False).returncode and len(log.read_text().splitlines())==5
        assert json.loads(invoke(env,"dispatch").stdout)["delivered"]==1 and len(log.read_text().splitlines())==6
        assert invoke(env,"remove","phone","wrong",ok=False).returncode
        invoke(env,"remove","phone","REMOVE NOTIFICATION phone"); assert len(json.loads(invoke(env,"list").stdout)["destinations"])==1
    print("Bedrock secure actionable notification tests passed.")
if __name__=="__main__": main()
