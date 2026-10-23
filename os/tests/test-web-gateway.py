#!/usr/bin/python3
"""Run inside the disposable systemd fixture while the real API is active."""
import hashlib
import http.client
import json
import os
import pathlib
import pwd
import re
import shutil
import socket
import ssl
import subprocess
import sys
import time
import uuid

assert os.environ.get("BEDROCK_DISPOSABLE_SERVICE_TEST") == "1" and pathlib.Path("/.dockerenv").exists()
assert os.geteuid() == 0
token = sys.stdin.read().strip()
assert len(token) == 64
root = pathlib.Path(__file__).resolve().parents[1] / "config/includes.chroot"
subprocess.run(["useradd", "--system", "--user-group", "--home-dir", "/nonexistent", "bedrock-web"], check=True)
for name in ("bedrock-web", "bedrock-web-identity"):
    shutil.copyfile(root / f"usr/lib/systemd/system/{name}.service", f"/etc/systemd/system/{name}.service")
helper = pathlib.Path("/usr/lib/bedrock/initialize-web-identity")
shutil.copyfile(root / "usr/lib/bedrock/initialize-web-identity", helper)
helper.chmod(0o755)
preparer = pathlib.Path("/usr/lib/bedrock/prepare-web-gateway")
shutil.copyfile(root / "usr/lib/bedrock/prepare-web-gateway", preparer)
preparer.chmod(0o755)
manager = pathlib.Path("/usr/lib/bedrock/manage-api-tokens")
shutil.copyfile(root / "usr/lib/bedrock/manage-api-tokens", manager)
manager.chmod(0o755)
for relative in ("usr/sbin/bedrock-update-settings", "usr/lib/bedrock/require-normal-mode", "usr/share/bedrock/default-update-policy.json"):
    installed = pathlib.Path("/") / relative
    shutil.copyfile(root / relative, installed)
    installed.chmod(0o644 if relative.endswith(".json") else 0o755)
relay_helper = pathlib.Path("/usr/lib/bedrock/configure-remote-relay")
shutil.copyfile(root / "usr/lib/bedrock/configure-remote-relay", relay_helper)
relay_helper.chmod(0o755)
relay_fixture = pathlib.Path("/usr/lib/bedrock/test-relay-connector")
relay_fixture.write_text("#!/bin/sh\nset -eu\n[ ! -e /run/bedrock-relay-fixture-fail ] || exit 1\nexec sleep infinity\n")
relay_fixture.chmod(0o755)
pathlib.Path("/etc/systemd/system/bedrock-relay-connector.service").write_text("""[Unit]
Description=Disposable Bedrock relay connector acceptance fixture
ConditionPathExists=/var/lib/bedrock/remote/relay.json
ConditionPathExists=/var/lib/bedrock/remote/relay-token

[Service]
Type=simple
ExecStartPre=/usr/bin/test ! -e /run/bedrock-relay-fixture-fail
ExecStart=/usr/lib/bedrock/test-relay-connector
""")
app_helper = pathlib.Path("/usr/lib/bedrock/change-app")
shutil.copyfile(root / "usr/lib/bedrock/change-app", app_helper)
app_helper.chmod(0o755)
app_manager = pathlib.Path("/usr/sbin/bedrock-apps")
shutil.copyfile(root / "usr/sbin/bedrock-apps", app_manager)
app_manager.chmod(0o755)
podman = pathlib.Path("/usr/bin/podman")
podman.write_text("""#!/bin/sh
set -eu
printf '%s\n' "$*" >> /var/lib/bedrock/apps/runtime-calls
case "${1:-}" in
  inspect) [ -f /var/lib/bedrock/apps/runtime-running ] && cat /var/lib/bedrock/apps/runtime-running || printf 'false\n' ;;
  start) printf 'true\n' > /var/lib/bedrock/apps/runtime-running ;;
  stop|rm) printf 'false\n' > /var/lib/bedrock/apps/runtime-running ;;
  create) if [ -e /run/bedrock-app-create-fail-once ]; then rm -f /run/bedrock-app-create-fail-once; exit 1; fi ;;
  pull) ;;
  *) exit 2 ;;
esac
""")
podman.chmod(0o755)
apps_state = pathlib.Path("/var/lib/bedrock/apps")
apps_state.mkdir(parents=True, exist_ok=True)
staged_app = {"id": "photos", "name": "Photos", "image": "registry.bedrock.test/apps/photos:1.0",
              "digest": "sha256:" + "a" * 64, "network": "bridge", "ports": [],
              "resources": {"cpus": 1, "memory_mib": 512, "pids": 128}, "update_policy": "notify"}
(apps_state / "staged-installs.json").write_text(json.dumps({"schema": 1, "apps": [staged_app]}))
subprocess.run([str(app_manager), "list"], check=True, stdout=subprocess.DEVNULL)
backup_helper = pathlib.Path("/usr/lib/bedrock/change-backup")
shutil.copyfile(root / "usr/lib/bedrock/change-backup", backup_helper)
backup_helper.chmod(0o755)
backup_manager = pathlib.Path("/usr/sbin/bedrock-backup")
shutil.copyfile(root / "usr/sbin/bedrock-backup", backup_manager)
backup_manager.chmod(0o755)
restic = pathlib.Path("/usr/bin/restic")
restic.write_text("""#!/usr/bin/python3
import json,pathlib,sys
state=pathlib.Path('/var/lib/bedrock/backup')
with (state/'restic-calls').open('a') as stream: stream.write(' '.join(sys.argv[1:])+'\\n')
args=sys.argv[1:]
marker=pathlib.Path('/run/bedrock-restic-fail-once')
if 'backup' in args and marker.exists(): marker.unlink(); raise SystemExit(1)
if 'init' in args: pathlib.Path(args[args.index('-r')+1]).mkdir(parents=True,exist_ok=True)
if 'snapshots' in args: print(json.dumps([{'id':'0123456789abcdef0123456789abcdef'}]))
if 'restore' in args: pathlib.Path(args[args.index('--target')+1]).mkdir(parents=True)
""")
restic.chmod(0o755)
backup_state = pathlib.Path("/var/lib/bedrock/backup")
backup_state.mkdir(parents=True, exist_ok=True)
(backup_state / "secrets").mkdir(exist_ok=True)
backup_password = backup_state / "secrets/nightly.password"
backup_password.write_text("fixture-backup-password")
backup_password.chmod(0o600)
backup_source = pathlib.Path("/srv/bedrock/backup-source")
backup_source.mkdir(parents=True, exist_ok=True)
(backup_source / "data.txt").write_text("backup acceptance data")
staged_backup = {"id": "nightly", "name": "Nightly files", "source": str(backup_source),
                 "repository": "/mnt/bedrock-backup-fixture", "kind": "local",
                 "schedule": {"frequency": "daily", "hour_utc": 0, "weekday": None},
                 "retention": {"daily": 7, "weekly": 4, "monthly": 6}, "initialize": True}
(backup_state / "staged-plans.json").write_text(json.dumps({"schema": 1, "plans": [staged_backup]}))
subprocess.run([str(backup_manager), "list"], check=True, stdout=subprocess.DEVNULL)
for name in ("change-vm-image", "convert-vm-image", "import-uploaded-vm-image", "import-vm-image", "collect-image-status"):
    installed = pathlib.Path("/usr/lib/bedrock") / name
    shutil.copyfile(root / "usr/lib/bedrock" / name, installed)
    installed.chmod(0o755)
qemu_img = pathlib.Path("/usr/bin/qemu-img")
qemu_img.write_text("""#!/usr/bin/python3
import json,pathlib,shutil,sys
args=sys.argv[1:]; formats=pathlib.Path('/run/bedrock-qemu-formats.json')
mapping=json.loads(formats.read_text()) if formats.exists() else {}
if args[0]=='info':
    source=pathlib.Path(args[-1]); print(json.dumps({'format':mapping.get(str(source),'raw'),'virtual-size':source.stat().st_size,'encrypted':False})); raise SystemExit
if args[0]=='convert':
    marker=pathlib.Path('/run/bedrock-qemu-convert-fail-once')
    if marker.exists(): marker.unlink(); raise SystemExit(1)
    source,target=pathlib.Path(args[-2]),pathlib.Path(args[-1]); shutil.copyfile(source,target)
    with target.open('ab') as stream: stream.write(b'-converted')
    mapping[str(target)]='qcow2' if args[args.index('-O')+1]=='qcow2' else 'raw'; formats.write_text(json.dumps(mapping)); raise SystemExit
raise SystemExit(2)
""")
qemu_img.chmod(0o755)
virtualization = pathlib.Path("/var/lib/bedrock/virtualization")
virtualization.mkdir(parents=True, exist_ok=True)
(virtualization / "images.json").write_text('{"schema":1,"images":[]}\n')
(virtualization / "image-provenance.json").write_text('{"schema":1,"conversions":[]}\n')
subprocess.run(["/usr/lib/bedrock/collect-image-status"], check=True, stdout=subprocess.DEVNULL)
storage_helper = pathlib.Path("/usr/lib/bedrock/change-storage")
shutil.copyfile(root / "usr/lib/bedrock/change-storage", storage_helper)
storage_helper.chmod(0o755)
storage_state = pathlib.Path("/var/lib/bedrock/storage")
storage_state.mkdir(parents=True, exist_ok=True)
(storage_state / "resources.json").write_text('{"schema":1,"pools":[]}\n')
storage_ids = [f"disk-{digit * 20}" for digit in "12345"]
storage_paths = [f"/dev/fixture-{digit}" for digit in "12345"]
(storage_state / "fixture-disks.json").write_text(json.dumps([
    {"id": disk_id, "path": path, "model": f"Fixture disk {index + 1}", "size_bytes": 1099511627776,
     "transport": "sata", "health": "healthy"}
    for index, (disk_id, path) in enumerate(zip(storage_ids, storage_paths))
]))
storage_manager = pathlib.Path("/usr/sbin/bedrock-storage")
storage_manager.write_text(r'''#!/usr/bin/python3
import json,pathlib,subprocess,sys,time,uuid
assert sys.argv[1]=='apply' and len(sys.argv)==3
request=json.loads(pathlib.Path(sys.argv[2]).read_text()); root=pathlib.Path('/var/lib/bedrock/storage')
state_path=root/'resources.json'; state=json.loads(state_path.read_text()); action=request['action']; now=int(time.time())
task=f"storage-{action}-{uuid.uuid4()}"; writer='/usr/lib/bedrock/record-api-task'
subprocess.run([writer,task,f'storage-{action}','queued',str(now),'0','3','steps'],check=True)
marker=pathlib.Path('/run/bedrock-storage-fail-once')
if marker.exists():
    marker.unlink(); subprocess.run([writer,task,f'storage-{action}','failed',str(now),'1','3','steps'],check=True); raise SystemExit(1)
pool=next((item for item in state['pools'] if item['name']==request['pool']),None)
if action=='create':
    assert pool is None; state['pools'].append({'name':request['pool'],'backend':request['backend'],'layout':request['layout'],'devices':request['devices'],'state':'online','last_scrub_unix':None,'last_operation_unix':now})
else:
    assert pool is not None
    if action=='expand': pool['devices']+=request['devices']
    elif action=='replace': pool['devices']=[item for item in pool['devices'] if item!=request['devices'][0]]+[request['devices'][1]]; pool['state']='rebuilding'
    elif action=='scrub': pool['last_scrub_unix']=now; pool['state']='online'
    elif action=='export': pool['state']='exported'
    elif action=='import': pool['state']='online'
    pool['last_operation_unix']=now
state_path.write_text(json.dumps(state,sort_keys=True,separators=(',',':'))+'\n')
subprocess.run([writer,task,f'storage-{action}','succeeded',str(now),'3','3','steps'],check=True)
''')
storage_manager.chmod(0o755)
storage_collector = pathlib.Path("/usr/lib/bedrock/collect-storage-health")
storage_collector.write_text(r'''#!/usr/bin/python3
import json,pathlib,time
root=pathlib.Path('/var/lib/bedrock/storage'); resources=json.loads((root/'resources.json').read_text())
disks=json.loads((root/'fixture-disks.json').read_text()); members={path for pool in resources['pools'] for path in pool['devices']}
candidates=[]
for disk in disks:
    managed=disk['path'] in members
    candidates.append({**disk,'eligible':not managed,'reason':'managed' if managed else 'available'})
(root/'candidates.json').write_text(json.dumps({'schema':1,'generated_unix':int(time.time()),'disks':candidates},sort_keys=True,separators=(',',':'))+'\n')
ids={disk['path']:disk['id'] for disk in disks}
public_candidates=[{key:item[key] for key in ('id','model','size_bytes','transport','health','eligible','reason')} for item in candidates]
managed=[{'name':pool['name'],'backend':pool['backend'],'layout':pool['layout'],'state':pool['state'],'members':[ids[path] for path in pool['devices']]} for pool in resources['pools']]
health={'schema':1,'generated_unix':int(time.time()),'overall':'healthy','read_only':True,
 'disks':[{'model':item['model'],'size_bytes':item['size_bytes'],'transport':item['transport'],'smart':{'available':True,'passed':True,'temperature_c':30,'power_on_hours':100,'power_mode':'ACTIVE','command_exit':0,'health':'healthy'}} for item in disks],
 'disk_candidates':public_candidates,'managed_pools':managed,
 'software_raid':{'md_arrays':[],'zfs':{'available':True,'pools':[]}},
 'hardware_raid':{'controllers':[],'management_tools':[],'vendor_reports':[],'explanation':'fixture'}}
(root/'health.json').write_text(json.dumps(health,sort_keys=True,separators=(',',':'))+'\n')
''')
storage_collector.chmod(0o755)
subprocess.run([str(storage_collector)], check=True, stdout=subprocess.DEVNULL)
pathlib.Path("/etc/bedrock").mkdir(exist_ok=True)
for name in ("web-gateway.conf", "web-proxy.conf"):
    shutil.copyfile(root / "etc/bedrock" / name, pathlib.Path("/etc/bedrock") / name)
dropin = pathlib.Path("/etc/systemd/system/nginx.service.d")
dropin.mkdir(exist_ok=True)
shutil.copyfile(root / "etc/systemd/system/nginx.service.d/bedrock.conf", dropin / "bedrock.conf")
ui = pathlib.Path("/usr/share/bedrock/management-ui")
shutil.copytree(root / "usr/share/bedrock/management-ui", ui)
manifest = json.loads((ui / "build-manifest.json").read_text())
subprocess.run(["systemctl", "daemon-reload"], check=True)
subprocess.run(["systemctl", "stop", "nginx"], check=True)
subprocess.run(["systemctl", "start", "nginx"], check=True)
assert subprocess.run(["systemctl", "is-active", "--quiet", "nginx"]).returncode != 0
try:
    with socket.create_connection(("127.0.0.1", 80), timeout=1):
        raise AssertionError("distribution HTTP listener is still active")
except ConnectionRefusedError:
    pass
subprocess.run(["systemctl", "start", "bedrock-web"], check=True)
certificate = pathlib.Path("/var/lib/bedrock/web/identity/server.crt")
context = ssl.create_default_context(cafile=str(certificate))


def request(method, path, body=None, headers=None):
    connection = http.client.HTTPSConnection("127.0.0.1", 8443, context=context, timeout=5)
    try:
        connection.request(method, path, body=body, headers=headers or {})
        result = connection.getresponse()
        return result.status, result.read(), dict(result.getheaders())
    finally:
        connection.close()


def wait_ready():
    for _ in range(100):
        try:
            if request("GET", "/")[0] == 200:
                return
        except OSError:
            pass
        time.sleep(0.05)
    raise AssertionError("HTTPS gateway did not start")


try:
    wait_ready()
    status, body, headers = request("GET", "/")
    assert status == 200 and body == (ui / "index.html").read_bytes()
    assert headers["X-Content-Type-Options"] == "nosniff"
    assert headers["Referrer-Policy"] == "no-referrer"
    assert "frame-ancestors 'none'" in headers["Content-Security-Policy"]
    for asset in manifest["files"]:
        status, payload, asset_headers = request("GET", "/" + asset["path"])
        assert status == 200 and len(payload) == asset["size_bytes"]
        assert hashlib.sha256(payload).hexdigest() == asset["sha256"], "gateway changed an installed UI asset"
        assert asset_headers["X-Content-Type-Options"] == "nosniff"
        if asset["path"].endswith(".js"):
            assert "javascript" in asset_headers["Content-Type"]
        if asset["path"].endswith(".css"):
            assert asset_headers["Content-Type"].startswith("text/css")
    auth = {"Authorization": f"Bearer {token}", "Origin": "https://127.0.0.1:8443", "Sec-Fetch-Site": "same-origin"}
    contract = json.loads((root / "usr/share/bedrock/api/openapi-v1.json").read_text())
    mutations = [(method.upper(), re.sub(r"\{[^}]+\}", "gateway-probe", path))
                 for path, operations in contract["paths"].items()
                 for method in operations if method in {"post", "put", "patch", "delete"}]
    assert len(mutations) == 33, "review frozen mutation inventory when contract routes change"
    protected_state = [pathlib.Path("/var/lib/bedrock/api") / name for name in ("tasks.json", "audit.jsonl")]
    protected_before = [path.read_bytes() for path in protected_state]
    for method, path in mutations:
        common = {"Content-Type": "application/json"}
        for denied_headers in (common, {**common, "Authorization": "Bearer " + "0" * 64}):
            status, body, _ = request(method, path, b"{}", denied_headers)
            assert status == 401 and json.loads(body)["error"] == "unauthorized", f"authorization gate failed: {method} {path}"
        status, _, _ = request(method, path, b"{}", {**common, **auth, "Origin": "https://attacker.invalid"})
        assert status == 403, f"origin gate failed: {method} {path}"
    assert [path.read_bytes() for path in protected_state] == protected_before, "denied route probes changed task/audit state"
    print("HTTPS mutation denial matrix passed: all 33 declared routes, missing/invalid tokens and foreign Origin; task/audit state unchanged.")
    assert request("GET", "/api/v1/images")[0] == 401
    assert request("GET", "/api/v1/images", headers={**auth, "Authorization": "Bearer " + "0" * 64})[0] == 401
    status, body, headers = request("GET", "/api/v1/images", headers=auth)
    assert status == 200 and json.loads(body)["schema"] == 1 and "ETag" in headers
    replacement = json.loads(subprocess.check_output(
        ["/usr/lib/bedrock/create-api-token", "gateway-replacement"], text=True))["token"]
    replacement_auth = {**auth, "Authorization": f"Bearer {replacement}"}
    assert request("GET", "/api/v1/images", headers=replacement_auth)[0] == 200
    subprocess.run([str(manager), "revoke", "gateway-replacement"], check=True, stdout=subprocess.DEVNULL)
    assert request("GET", "/api/v1/images", headers=replacement_auth)[0] == 401
    renewed = json.loads(subprocess.check_output(
        ["/usr/lib/bedrock/create-api-token", "gateway-replacement"], text=True))["token"]
    assert renewed != replacement
    assert request("GET", "/api/v1/images", headers={**auth, "Authorization": f"Bearer {renewed}"})[0] == 200
    assert request("GET", "/api/v1/images", headers=replacement_auth)[0] == 401
    subprocess.run([str(manager), "revoke", "gateway-replacement"], check=True, stdout=subprocess.DEVNULL)
    assert request("GET", "/api/v1/images", headers=auth)[0] == 200
    del replacement, replacement_auth, renewed
    assert request("GET", "/api/v1/images", headers={**auth, "Origin": "https://attacker.invalid"})[0] == 403
    assert request("GET", "/api/v1/images", headers={**auth, "Origin": "null"})[0] == 403
    assert request("GET", "/api/v1/images", headers={**auth, "Sec-Fetch-Site": "cross-site"})[0] == 403
    assert request("GET", "/api/v1/images", headers={**auth, "Host": "attacker.invalid:8443"})[0] == 421
    assert request("GET", "/.git/config")[0] == 404
    assert request("GET", "/build-manifest.json")[0] == 404
    assert request("GET", "/var/lib/bedrock/api/tokens.json")[0] == 404
    assert request("POST", "/api/v1/settings", b"x" * 65537, auth)[0] == 413
    # Exercise mutations through nginx, including an upload above the ordinary 64 KiB limit.
    task_file = pathlib.Path("/var/lib/bedrock/api/tasks.json")
    audit_file = task_file.with_name("audit.jsonl")
    tasks_before = len(json.loads(task_file.read_text())["tasks"])
    events_before = len(audit_file.read_text().splitlines())
    upload_path = "/api/v1/images/gateway-upload/upload"
    _, _, before_headers = request("GET", "/api/v1/images", headers=auth)
    upload_headers = {**auth, "Content-Type": "application/octet-stream", "X-Bedrock-Image-Type": "iso", "If-Match": before_headers["ETag"]}
    assert request("PUT", upload_path, b"denied", {**upload_headers, "Authorization": "Bearer " + "0" * 64})[0] == 401
    assert request("PUT", upload_path, b"stale", {**upload_headers, "If-Match": '"stale"'})[0] == 412
    payload = b"gateway-streaming-acceptance\n" * 3000
    assert len(payload) > 65536
    assert request("PUT", upload_path, payload, upload_headers)[0] == 200
    staged = pathlib.Path("/var/lib/bedrock/virtualization/uploads/gateway-upload.iso")
    assert staged.read_bytes() == payload
    digest = hashlib.sha256(payload).hexdigest()
    _, _, refreshed = request("GET", "/api/v1/images", headers=auth)
    assert refreshed["ETag"] != before_headers["ETag"]
    discard = {"schema": 1, "sha256": digest, "confirmation": f"DISCARD IMAGE UPLOAD gateway-upload {digest}"}
    discard_headers = {**auth, "Content-Type": "application/json", "If-Match": refreshed["ETag"]}
    assert request("DELETE", upload_path, json.dumps(discard), {**discard_headers, "If-Match": before_headers["ETag"]})[0] == 412
    assert request("DELETE", upload_path, json.dumps({**discard, "confirmation": "wrong"}), discard_headers)[0] == 400
    assert staged.read_bytes() == payload
    assert request("DELETE", upload_path, json.dumps(discard), discard_headers)[0] == 200
    assert not staged.exists()
    assert request("DELETE", upload_path, json.dumps(discard), discard_headers)[0] == 412
    assert len(json.loads(task_file.read_text())["tasks"]) == tasks_before + 2
    events = [json.loads(line) for line in audit_file.read_text().splitlines()]
    assert len(events) == events_before + 2
    assert {event["action"] for event in events[-2:]} == {"image-upload", "image-discard"}
    settings_tasks = len(json.loads(task_file.read_text())["tasks"])
    settings_audit = len(audit_file.read_text().splitlines())
    def settings_request(body, key, match=None):
        if match is None:
            code, _, current = request("GET", "/api/v1/settings", headers=auth)
            assert code == 200
            match = current["ETag"]
        return request("PUT", "/api/v1/settings", json.dumps(body),
                       {**auth, "Content-Type": "application/json", "Idempotency-Key": key, "If-Match": match})
    change = {"schema": 1, "setting": "automatic_checks", "value": True, "beta_risk_acknowledged": False}
    key = str(uuid.uuid4())
    assert settings_request(change, key, '"stale"')[0] == 412
    assert settings_request({**change, "unexpected": True}, key)[0] == 400
    assert settings_request(change, key)[0] == 200
    policy = pathlib.Path("/var/lib/bedrock/settings/update-policy.json")
    assert json.loads(policy.read_text())["automatic_checks"] is True
    code, replay, _ = settings_request(change, key)
    assert code == 200 and json.loads(replay)["replayed"] is True
    assert settings_request({**change, "value": False}, key)[0] == 409
    assert json.loads(policy.read_text())["automatic_checks"] is True
    assert settings_request({**change, "value": False}, str(uuid.uuid4()))[0] == 200
    beta = {"schema": 1, "setting": "channel", "value": "beta", "beta_risk_acknowledged": False}
    assert settings_request(beta, str(uuid.uuid4()))[0] == 400
    assert json.loads(policy.read_text())["channel"] == "stable"
    assert settings_request({**beta, "beta_risk_acknowledged": True}, str(uuid.uuid4()))[0] == 200
    assert json.loads(policy.read_text())["channel"] == "beta"
    assert settings_request({**beta, "value": "stable"}, str(uuid.uuid4()))[0] == 200
    assert json.loads(policy.read_text())["channel"] == "stable"
    assert json.loads(policy.read_text())["automatic_checks"] is False
    assert len(json.loads(task_file.read_text())["tasks"]) == settings_tasks + 4
    settings_events = [json.loads(line) for line in audit_file.read_text().splitlines()]
    assert len(settings_events) == settings_audit + 4
    assert all(event["action"] == "update-policy" for event in settings_events[-4:])
    print("HTTPS update-policy mutations passed: real policy changes, stale/malformed denial, replay/conflict, beta acknowledgement, four terminal audit events.")
    relay_tasks = len(json.loads(task_file.read_text())["tasks"])
    relay_audit = len(audit_file.read_text().splitlines())
    route = "42345678-1234-4123-8123-123456789abc"
    relay_token = "relay_https_secret_ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789"
    relay = {"schema": 1, "operation": "configure", "host": "relay.bedrock.test", "port": 443,
             "server_route": route, "token": relay_token,
             "confirmation": f"CONFIGURE REMOTE RELAY relay.bedrock.test:443 ROUTE {route}"}
    relay_key = str(uuid.uuid4())
    assert settings_request({**relay, "confirmation": "wrong"}, str(uuid.uuid4()))[0] == 400
    assert settings_request(relay, relay_key, '"stale"')[0] == 412
    code, relay_result, _ = settings_request(relay, relay_key)
    assert code == 200 and json.loads(relay_result)["replayed"] is False
    relay_config = pathlib.Path("/var/lib/bedrock/remote/relay.json")
    relay_secret = relay_config.with_name("relay-token")
    assert json.loads(relay_config.read_text())["server_route"] == route
    assert relay_secret.read_text().strip() == relay_token
    assert oct(relay_config.stat().st_mode & 0o777) == "0o600" and oct(relay_secret.stat().st_mode & 0o777) == "0o600"
    code, settings_body, _ = request("GET", "/api/v1/settings", headers=auth)
    assert code == 200 and json.loads(settings_body)["remote_relay"] == {"configured": True}
    code, replay, _ = settings_request(relay, relay_key)
    assert code == 200 and json.loads(replay)["replayed"] is True
    assert settings_request({**relay, "token": "changed_relay_secret_ABCDEFGHIJKLMNOPQRSTUVWXYZ_012345"}, relay_key)[0] == 409
    for exposed in (relay_result, replay, task_file.read_bytes(), audit_file.read_bytes(), pathlib.Path("/var/lib/bedrock/api/action-results.json").read_bytes(), relay_config.read_bytes()):
        assert relay_token.encode() not in exposed
    previous_config, previous_token = relay_config.read_bytes(), relay_secret.read_bytes()
    failure_marker = pathlib.Path("/run/bedrock-relay-fixture-fail")
    failure_marker.touch()
    failed = {**relay, "server_route": "52345678-1234-4123-8123-123456789abc",
              "token": "failed_relay_secret_ABCDEFGHIJKLMNOPQRSTUVWXYZ_012345",
              "confirmation": "CONFIGURE REMOTE RELAY relay.bedrock.test:443 ROUTE 52345678-1234-4123-8123-123456789abc"}
    try:
        assert settings_request(failed, str(uuid.uuid4()))[0] == 422
    finally:
        failure_marker.unlink(missing_ok=True)
    assert relay_config.read_bytes() == previous_config and relay_secret.read_bytes() == previous_token
    subprocess.run(["systemctl", "restart", "bedrock-relay-connector.service"], check=True)
    disable = {"schema": 1, "operation": "disable", "confirmation": "DISABLE REMOTE RELAY"}
    assert settings_request({**disable, "confirmation": "wrong"}, str(uuid.uuid4()))[0] == 400
    assert settings_request(disable, str(uuid.uuid4()))[0] == 200
    assert not relay_config.exists() and not relay_secret.exists()
    assert subprocess.run(["systemctl", "is-active", "--quiet", "bedrock-relay-connector.service"]).returncode != 0
    code, settings_body, _ = request("GET", "/api/v1/settings", headers=auth)
    assert code == 200 and json.loads(settings_body)["remote_relay"] == {"configured": False}
    relay_events = [json.loads(line) for line in audit_file.read_text().splitlines()[relay_audit:]]
    assert len(json.loads(task_file.read_text())["tasks"]) == relay_tasks + 3
    assert len(relay_events) == 3 and [event["action"] for event in relay_events] == ["remote-relay-configure", "remote-relay-configure", "remote-relay-disable"]
    assert [event["outcome"] for event in relay_events] == ["succeeded", "failed", "succeeded"]
    print("HTTPS relay mutations passed: configure/replay/conflict, secret containment, failed-restart rollback, disable, and terminal task/audit outcomes.")
    app_tasks = len(json.loads(task_file.read_text())["tasks"])
    app_audit = len(audit_file.read_text().splitlines())
    def app_request(method, path, body, key=None, match=None):
        if match is None:
            code, _, current = request("GET", "/api/v1/apps", headers=auth)
            assert code == 200
            match = current["ETag"]
        return request(method, path, json.dumps(body),
                       {**auth, "Content-Type": "application/json", "Idempotency-Key": key or str(uuid.uuid4()), "If-Match": match})
    install_path = "/api/v1/apps/photos/install"
    install = {"schema": 1, "confirmation": "INSTALL APPLICATION photos"}
    assert app_request("POST", install_path, {**install, "confirmation": "wrong"})[0] == 400
    assert app_request("POST", install_path, install, match='"stale"')[0] == 412
    install_key = str(uuid.uuid4())
    code, installed, _ = app_request("POST", install_path, install, install_key)
    if code != 200 or json.loads(installed).get("replayed") is not False:
        app_diagnostics = {
            "status": code,
            "response": installed.decode(errors="replace"),
            "staged": (apps_state / "staged-installs.json").read_text() if (apps_state / "staged-installs.json").exists() else "missing",
            "runtime_calls": (apps_state / "runtime-calls").read_text() if (apps_state / "runtime-calls").exists() else "missing",
            "recent_tasks": json.loads(task_file.read_text())["tasks"][-2:],
        }
        raise AssertionError(f"staged application install failed: {app_diagnostics}")
    code, apps_body, _ = request("GET", "/api/v1/apps", headers=auth)
    apps_feed = json.loads(apps_body)
    assert code == 200 and apps_feed["install_candidates"] == []
    assert len(apps_feed["apps"]) == 1 and apps_feed["apps"][0]["id"] == "photos" and apps_feed["apps"][0]["running"] is True
    assert "image" not in apps_body.decode() and "digest" not in apps_body.decode()
    code, replay, _ = app_request("POST", install_path, install, install_key)
    assert code == 200 and json.loads(replay)["replayed"] is True
    power_path = "/api/v1/apps/photos/power"
    stop = {"schema": 1, "operation": "stop", "confirmation": "STOP APPLICATION photos"}
    assert app_request("POST", power_path, stop, install_key)[0] == 409
    assert app_request("POST", power_path, stop)[0] == 200
    assert json.loads(request("GET", "/api/v1/apps", headers=auth)[1])["apps"][0]["running"] is False
    start = {"schema": 1, "operation": "start", "confirmation": "START APPLICATION photos"}
    assert app_request("POST", power_path, start)[0] == 200
    assert json.loads(request("GET", "/api/v1/apps", headers=auth)[1])["apps"][0]["running"] is True
    candidate_file = apps_state / "update-candidates.json"
    candidate_file.write_text(json.dumps({"schema": 1, "candidates": {"photos": "sha256:" + "b" * 64}}))
    subprocess.run([str(app_manager), "list"], check=True, stdout=subprocess.DEVNULL)
    update_path = "/api/v1/apps/photos/update"
    update = {"schema": 1, "confirmation": "UPDATE APPLICATION photos"}
    assert app_request("POST", update_path, update)[0] == 200
    app_state_file = apps_state / "apps.json"
    assert json.loads(app_state_file.read_text())["apps"][0]["digest"] == "sha256:" + "b" * 64
    candidate_file.write_text(json.dumps({"schema": 1, "candidates": {"photos": "sha256:" + "c" * 64}}))
    subprocess.run([str(app_manager), "list"], check=True, stdout=subprocess.DEVNULL)
    pathlib.Path("/run/bedrock-app-create-fail-once").touch()
    assert app_request("POST", update_path, update)[0] == 422
    assert json.loads(app_state_file.read_text())["apps"][0]["digest"] == "sha256:" + "b" * 64
    assert json.loads(request("GET", "/api/v1/apps", headers=auth)[1])["apps"][0]["update_available"] is True
    remove_path = "/api/v1/apps/photos"
    remove = {"schema": 1, "confirmation": "REMOVE APPLICATION photos"}
    assert app_request("DELETE", remove_path, remove)[0] == 200
    assert json.loads(request("GET", "/api/v1/apps", headers=auth)[1])["apps"] == []
    assert pathlib.Path("/srv/bedrock/apps/photos").is_dir(), "application data was not preserved on removal"
    assert not any(path.name.endswith(".json") for path in pathlib.Path("/var/lib/bedrock/apps/requests").iterdir())
    app_events = [json.loads(line) for line in audit_file.read_text().splitlines()[app_audit:]]
    assert len(json.loads(task_file.read_text())["tasks"]) == app_tasks + 6
    assert len(app_events) == 6
    assert [event["action"] for event in app_events] == ["app-install-staged", "app-stop", "app-start", "app-update-latest", "app-update-latest", "app-remove"]
    assert [event["outcome"] for event in app_events] == ["succeeded", "succeeded", "succeeded", "succeeded", "failed", "succeeded"]
    print("HTTPS application mutations passed: staged install, power, update, failed-update rollback, data-preserving removal, refresh, replay/conflict, and terminal audit outcomes.")
    backup_tasks = len(json.loads(task_file.read_text())["tasks"])
    backup_audit = len(audit_file.read_text().splitlines())
    def backup_request(path, body, key=None, match=None):
        if match is None:
            code, _, current = request("GET", "/api/v1/backups", headers=auth)
            assert code == 200
            match = current["ETag"]
        return request("POST", path, json.dumps(body),
                       {**auth, "Content-Type": "application/json", "Idempotency-Key": key or str(uuid.uuid4()), "If-Match": match})
    create_path = "/api/v1/backups/nightly/create"
    create = {"schema": 1, "confirmation": "CREATE ENCRYPTED BACKUP nightly"}
    assert backup_request(create_path, {**create, "confirmation": "wrong"})[0] == 400
    assert backup_request(create_path, create, match='"stale"')[0] == 412
    create_key = str(uuid.uuid4())
    assert backup_request(create_path, create, create_key)[0] == 200
    code, backups_body, _ = request("GET", "/api/v1/backups", headers=auth)
    backups_feed = json.loads(backups_body)
    assert code == 200 and backups_feed["create_candidates"] == [] and len(backups_feed["plans"]) == 1
    assert not any(secret in backups_body.decode() for secret in ("source", "repository", "password", "last_snapshot"))
    code, replay, _ = backup_request(create_path, create, create_key)
    assert code == 200 and json.loads(replay)["replayed"] is True
    run_path = "/api/v1/backups/nightly/run"
    run_backup = {"schema": 1, "confirmation": "RUN ENCRYPTED BACKUP nightly"}
    assert backup_request(run_path, run_backup, create_key)[0] == 409
    assert backup_request(run_path, run_backup)[0] == 200
    plan_state = backup_state / "plans.json"
    completed_plan = json.loads(plan_state.read_text())["plans"][0]
    assert completed_plan["last_snapshot"] == "0123456789abcdef0123456789abcdef" and completed_plan["last_success_unix"] is not None
    pathlib.Path("/run/bedrock-restic-fail-once").touch()
    before_failed_run = plan_state.read_bytes()
    assert backup_request(run_path, run_backup)[0] == 422
    assert plan_state.read_bytes() == before_failed_run
    restore_path = "/api/v1/backups/nightly/restore-latest"
    restore = {"schema": 1, "confirmation": "RESTORE LATEST BACKUP nightly"}
    assert backup_request(restore_path, restore)[0] == 200
    restored = pathlib.Path("/srv/bedrock/restores/nightly")
    assert restored.is_dir()
    restic_calls = (backup_state / "restic-calls").read_text()
    assert "fixture-backup-password" not in restic_calls and " backup " in restic_calls and "forget --prune" in restic_calls and " restore " in restic_calls
    assert not any(path.name.endswith(".json") for path in (backup_state / "requests").iterdir())
    backup_events = [json.loads(line) for line in audit_file.read_text().splitlines()[backup_audit:]]
    assert len(json.loads(task_file.read_text())["tasks"]) == backup_tasks + 4
    assert len(backup_events) == 4
    assert [event["action"] for event in backup_events] == ["backup-create", "backup-run", "backup-run", "backup-restore-latest"]
    assert [event["outcome"] for event in backup_events] == ["succeeded", "succeeded", "failed", "succeeded"]
    print("HTTPS backup mutations passed: staged creation, encrypted run/retention, failed-run state preservation, latest restore, secret-free refresh, replay/conflict, and terminal audit outcomes.")
    image_tasks = len(json.loads(task_file.read_text())["tasks"])
    image_audit = len(audit_file.read_text().splitlines())
    disk_name = "gateway-disk"
    disk_payload = b"bedrock-raw-disk-image-acceptance"
    disk_hash = hashlib.sha256(disk_payload).hexdigest()
    disk_upload_path = f"/api/v1/images/{disk_name}/upload"
    _, _, disk_before = request("GET", "/api/v1/images", headers=auth)
    disk_upload_headers = {**auth, "Content-Type": "application/octet-stream", "X-Bedrock-Image-Type": "img", "If-Match": disk_before["ETag"]}
    assert request("PUT", disk_upload_path, disk_payload, disk_upload_headers)[0] == 200
    _, _, uploaded_state = request("GET", "/api/v1/images", headers=auth)
    import_path = f"/api/v1/images/{disk_name}/import"
    import_body = {"schema": 1, "confirmation": f"IMPORT IMG {disk_name} {disk_hash}"}
    import_headers = {**auth, "Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4()), "If-Match": uploaded_state["ETag"]}
    assert request("POST", import_path, json.dumps({**import_body, "confirmation": "wrong"}), {**import_headers, "Idempotency-Key": str(uuid.uuid4())})[0] == 400
    assert request("POST", import_path, json.dumps(import_body), {**import_headers, "Idempotency-Key": str(uuid.uuid4()), "If-Match": '"stale"'})[0] == 412
    import_result = request("POST", import_path, json.dumps(import_body), import_headers)
    assert import_result[0] == 200, {
        "response": (import_result[0], import_result[1].decode(errors="replace")),
        "upload": (virtualization / f"uploads/{disk_name}.img").exists(),
        "manifest": (virtualization / f"uploads/{disk_name}.json").exists(),
        "request": (virtualization / f"requests/import-{disk_name}.json").exists(),
        "lock": (virtualization / f"uploads/.{disk_name}.import.lock").exists(),
        "library": (virtualization / f"images/{disk_name}.img").exists(),
        "state": (virtualization / "images.json").read_text(),
        "qemu_formats": pathlib.Path("/run/bedrock-qemu-formats.json").read_text() if pathlib.Path("/run/bedrock-qemu-formats.json").exists() else None,
        "tasks": json.loads(task_file.read_text())["tasks"][-2:],
    }
    imported_file = virtualization / f"images/{disk_name}.img"
    assert imported_file.read_bytes() == disk_payload
    assert not (virtualization / f"uploads/{disk_name}.img").exists() and not (virtualization / f"uploads/{disk_name}.json").exists()
    code, images_body, imported_state = request("GET", "/api/v1/images", headers=auth)
    images_feed = json.loads(images_body)
    imported = next(item for item in images_feed["images"] if item["name"] == disk_name)
    assert code == 200 and imported == {"name": disk_name, "type": "img", "sha256": disk_hash, "size_bytes": len(disk_payload), "converted": False}
    code, import_replay, _ = request("POST", import_path, json.dumps(import_body), {**import_headers, "If-Match": imported_state["ETag"]})
    assert code == 200 and json.loads(import_replay)["replayed"] is True
    convert_path = f"/api/v1/images/{disk_name}/convert"
    convert_body = {"schema": 1, "target": "gateway-converted", "target_type": "qcow2", "source_sha256": disk_hash,
                    "confirmation": f"CONVERT IMAGE {disk_name} {disk_hash} TO QCOW2 gateway-converted"}
    assert request("POST", convert_path, json.dumps(convert_body), {**auth, "Content-Type": "application/json", "Idempotency-Key": import_headers["Idempotency-Key"], "If-Match": imported_state["ETag"]})[0] == 409
    convert_headers = {**auth, "Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4()), "If-Match": imported_state["ETag"]}
    assert request("POST", convert_path, json.dumps(convert_body), convert_headers)[0] == 200
    code, images_body, converted_state = request("GET", "/api/v1/images", headers=auth)
    converted_feed = json.loads(images_body)
    converted = next(item for item in converted_feed["images"] if item["name"] == "gateway-converted")
    assert code == 200 and converted["type"] == "qcow2" and converted["converted"] is True
    provenance = json.loads((virtualization / "image-provenance.json").read_text())["conversions"]
    assert len(provenance) == 1 and provenance[0]["source"] == disk_name and provenance[0]["target"] == "gateway-converted"
    pathlib.Path("/run/bedrock-qemu-convert-fail-once").touch()
    failed_convert = {**convert_body, "target": "gateway-failed", "confirmation": f"CONVERT IMAGE {disk_name} {disk_hash} TO QCOW2 gateway-failed"}
    failed_headers = {**auth, "Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4()), "If-Match": converted_state["ETag"]}
    images_before_failure = (virtualization / "images.json").read_bytes()
    provenance_before_failure = (virtualization / "image-provenance.json").read_bytes()
    assert request("POST", convert_path, json.dumps(failed_convert), failed_headers)[0] == 422
    assert (virtualization / "images.json").read_bytes() == images_before_failure
    assert (virtualization / "image-provenance.json").read_bytes() == provenance_before_failure
    assert not (virtualization / "images/gateway-failed.qcow2").exists()
    image_events = [json.loads(line) for line in audit_file.read_text().splitlines()[image_audit:]]
    assert len(json.loads(task_file.read_text())["tasks"]) == image_tasks + 4
    assert len(image_events) == 4
    assert [event["action"] for event in image_events] == ["image-upload", "image-import", "image-convert", "image-convert"]
    assert [event["outcome"] for event in image_events] == ["succeeded", "succeeded", "succeeded", "failed"]
    print("HTTPS image mutations passed: upload/import, checksum-bound conversion/provenance, failed-conversion rollback, refresh, replay/conflict, and terminal audit outcomes.")
    storage_tasks = len(json.loads(task_file.read_text())["tasks"])
    storage_audit = len(audit_file.read_text().splitlines())

    def storage_request(method, path, body, key=None, match=None):
        if match is None:
            code, _, current = request("GET", "/api/v1/storage", headers=auth)
            assert code == 200
            match = current["ETag"]
        headers = {**auth, "Content-Type": "application/json", "Idempotency-Key": key or str(uuid.uuid4()), "If-Match": match}
        return request(method, path, json.dumps(body), headers)

    storage_name = "gateway-pool"
    create_storage = {"schema": 1, "id": storage_name, "backend": "zfs", "layout": "mirror",
                      "disk_ids": storage_ids[:2],
                      "confirmation": f"CREATE STORAGE {storage_name} USING {','.join(storage_ids[:2])}"}
    assert storage_request("POST", "/api/v1/storage", {**create_storage, "confirmation": "wrong"})[0] == 400
    assert storage_request("POST", "/api/v1/storage", create_storage, match='"stale"')[0] == 412
    create_storage_key = str(uuid.uuid4())
    assert storage_request("POST", "/api/v1/storage", create_storage, create_storage_key)[0] == 200
    code, storage_body, _ = request("GET", "/api/v1/storage", headers=auth)
    storage_feed = json.loads(storage_body)
    pool = next(item for item in storage_feed["managed_pools"] if item["name"] == storage_name)
    assert code == 200 and pool["state"] == "online" and pool["members"] == storage_ids[:2]
    code, replay, _ = storage_request("POST", "/api/v1/storage", create_storage, create_storage_key)
    assert code == 200 and json.loads(replay)["replayed"] is True
    scrub_path = f"/api/v1/storage/{storage_name}/scrub"
    scrub_storage = {"schema": 1, "confirmation": f"SCRUB STORAGE {storage_name}"}
    assert storage_request("POST", scrub_path, scrub_storage, create_storage_key)[0] == 409
    pathlib.Path("/run/bedrock-storage-fail-once").touch()
    resources_before_failure = (storage_state / "resources.json").read_bytes()
    assert storage_request("POST", scrub_path, scrub_storage)[0] == 422
    assert (storage_state / "resources.json").read_bytes() == resources_before_failure
    assert storage_request("POST", scrub_path, scrub_storage)[0] == 200
    expand_path = f"/api/v1/storage/{storage_name}/expand"
    expand_storage = {"schema": 1, "disk_ids": storage_ids[2:4],
                      "confirmation": f"EXPAND STORAGE {storage_name} USING {','.join(storage_ids[2:4])}"}
    assert storage_request("POST", expand_path, expand_storage)[0] == 200
    export_path = f"/api/v1/storage/{storage_name}/export"
    export_storage = {"schema": 1, "confirmation": f"EXPORT STORAGE {storage_name}"}
    assert storage_request("POST", export_path, export_storage)[0] == 200
    import_storage_path = f"/api/v1/storage/{storage_name}/import"
    import_storage = {"schema": 1, "confirmation": f"IMPORT STORAGE {storage_name}"}
    assert storage_request("POST", import_storage_path, import_storage)[0] == 200
    replace_path = f"/api/v1/storage/{storage_name}/replace"
    replace_storage = {"schema": 1, "old_disk_id": storage_ids[0], "new_disk_id": storage_ids[4],
                       "confirmation": f"REPLACE STORAGE {storage_name} MEMBER {storage_ids[0]} WITH {storage_ids[4]}"}
    assert storage_request("POST", replace_path, replace_storage)[0] == 200
    code, storage_body, _ = request("GET", "/api/v1/storage", headers=auth)
    storage_feed = json.loads(storage_body)
    pool = next(item for item in storage_feed["managed_pools"] if item["name"] == storage_name)
    assert code == 200 and pool["state"] == "rebuilding" and pool["members"] == storage_ids[1:]
    assert all("path" not in item for item in storage_feed["disk_candidates"])
    assert not any(path.name.endswith(".json") for path in (storage_state / "requests").iterdir())
    storage_events = [json.loads(line) for line in audit_file.read_text().splitlines()[storage_audit:]]
    assert len(json.loads(task_file.read_text())["tasks"]) == storage_tasks + 7
    assert len(storage_events) == 7
    assert [event["action"] for event in storage_events] == ["storage-create", "storage-scrub", "storage-scrub", "storage-expand", "storage-export", "storage-import", "storage-replace"]
    assert [event["outcome"] for event in storage_events] == ["succeeded", "failed", "succeeded", "succeeded", "succeeded", "succeeded", "succeeded"]
    print("HTTPS storage mutations passed: create/scrub/expand/export/import/replace, failure rollback, opaque disk identities, refresh, replay/conflict, and terminal audit outcomes.")
    websocket = {**auth, "Connection": "Upgrade", "Upgrade": "websocket", "Sec-WebSocket-Version": "13",
                 "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==", "Sec-WebSocket-Protocol": "binary"}
    assert request("GET", "/api/v1/vms/guest/console", headers=websocket)[0] == 400
    assert request("GET", "/api/v1/vms/guest/console", headers={**websocket, "Origin": "https://attacker.invalid"})[0] == 403
    pid = int(subprocess.check_output(["systemctl", "show", "--property=MainPID", "--value", "bedrock-web"]))
    process = dict(line.split(":", 1) for line in pathlib.Path(f"/proc/{pid}/status").read_text().splitlines() if ":" in line)
    assert all(int(value) == pwd.getpwnam("bedrock-web").pw_uid for value in process["Uid"].split())
    assert int(process["CapBnd"].strip(), 16) == 0 and process["NoNewPrivs"].strip() == "1"
    identity_before = hashlib.sha256(certificate.read_bytes()).hexdigest()
    subprocess.run(["systemctl", "restart", "bedrock-web"], check=True)
    wait_ready()
    assert request("GET", "/api/v1/images", headers=auth)[0] == 200
    assert hashlib.sha256(certificate.read_bytes()).hexdigest() == identity_before
    # Check access with the running service's mount namespace and UID/groups.
    pid = int(subprocess.check_output(["systemctl", "show", "--property=MainPID", "--value", "bedrock-web"]))
    account = pwd.getpwnam("bedrock-web")
    sandbox_reader = [
        "nsenter", f"--target={pid}", "--mount", "setpriv",
        f"--reuid={account.pw_uid}", f"--regid={account.pw_gid}", "--groups=bedrock-api",
        "python3", "-c", "import pathlib,sys; pathlib.Path(sys.argv[1]).open('rb').close()",
    ]
    # Positive control prevents a broken nsenter/setpriv invocation from passing denials.
    subprocess.run(sandbox_reader + ["/run/credentials/bedrock-web.service/tls-cert"], check=True)
    for protected in ("/var/lib/bedrock/web/identity/server.key", "/var/lib/bedrock/api/tokens.json"):
        denied = subprocess.run(sandbox_reader + [protected], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert denied.returncode != 0, f"gateway UID can read protected state: {protected}"
    # A bad persistent identity must fail closed without replacing owner trust.
    subprocess.run(["systemctl", "stop", "bedrock-web"], check=True)
    private_key = certificate.with_name("server.key")
    saved_key = private_key.with_name("server.key.saved")
    private_key.rename(saved_key)
    try:
        private_key.symlink_to(saved_key.name)
        assert subprocess.run([str(helper)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0
        assert private_key.is_symlink() and hashlib.sha256(certificate.read_bytes()).hexdigest() == identity_before
    finally:
        private_key.unlink()
        saved_key.rename(private_key)
    for unsafe_mode in (0o640, 0o644):
        private_key.chmod(unsafe_mode)
        try:
            assert subprocess.run([str(helper)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0
            assert private_key.stat().st_mode & 0o777 == unsafe_mode
            assert hashlib.sha256(certificate.read_bytes()).hexdigest() == identity_before
        finally:
            private_key.chmod(0o600)
    os.link(private_key, saved_key)
    try:
        assert subprocess.run([str(helper)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0
    finally:
        saved_key.unlink()
    subprocess.run(["systemctl", "start", "bedrock-web"], check=True)
    wait_ready()
    for scenario in ("issue", "decline", "failure"):
        subprocess.run(["python3", str(pathlib.Path(__file__).with_name("test-management-console.py")), scenario], check=True, timeout=45)
    subprocess.run(["python3", str(pathlib.Path(__file__).with_name("test-installed-browser.py"))], input=token, text=True, check=True, timeout=180)
    print("HTTPS gateway passed: trusted local TLS, real API authorization, origin/host checks, request limits, no default HTTP site, stable identity and unprivileged service.")
finally:
    subprocess.run(["systemctl", "stop", "bedrock-web"], check=True)
