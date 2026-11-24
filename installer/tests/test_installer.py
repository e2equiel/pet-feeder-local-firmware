"""Installation boundaries, transfer integrity and loopback UI protections."""
import base64
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pet_feeder_installer.bundle import Bundle, FLASH_SIZE, PARTITION_SIZES, STOCK_SHA256
from pet_feeder_installer.device import Installer
from pet_feeder_installer.telnet import DeviceError, Telnet, local_address
from pet_feeder_installer.wizard import Wizard, make_server


def make_bundle(directory):
    for name, content in {"pf_local.so": b"\x7fELF\x01test", "boot.sh": b"#!/bin/sh\n", "uninstall.sh": b"#!/bin/sh\n"}.items():
        (directory / name).write_bytes(content)
    manifest = {"format":1,"version":"0.2.0","stock_application_sha256":STOCK_SHA256,
                "partition_sizes":list(PARTITION_SIZES),
                "files":{name:hashlib.sha256((directory/name).read_bytes()).hexdigest() for name in ("pf_local.so","boot.sh","uninstall.sh")}}
    (directory/"release.json").write_text(json.dumps(manifest))
    return Bundle.load(directory)


class BoundaryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self.tmp.name)
        self.bundle = make_bundle(self.directory)
        self.transport = Mock(host="192.168.1.123")
        self.installer = Installer(self.transport, self.bundle, Mock())

    def tearDown(self):
        self.tmp.cleanup()

    def test_only_one_private_ipv4_target(self):
        for value in ("192.168.1.123","10.1.2.3","172.16.1.2"):
            self.assertEqual(local_address(value),value)
        for value in ("8.8.8.8","127.0.0.1","169.254.1.2","feeder.local","192.168.1.0/24","::1","192.168.1.2; reboot"):
            with self.assertRaises(DeviceError): local_address(value)

    def test_damaged_release_is_rejected(self):
        (self.directory/"boot.sh").write_text("tampered")
        with self.assertRaises(DeviceError): Bundle.load(self.directory)

    def test_release_cannot_add_an_arbitrary_path(self):
        path = self.directory/"release.json"
        manifest=json.loads(path.read_text());manifest["files"]["../../outside"]="0"*64
        path.write_text(json.dumps(manifest))
        with self.assertRaises(DeviceError): Bundle.load(self.directory)

    def test_unknown_flash_layout_stops_before_any_write(self):
        self.transport.run.side_effect=["base64\nsha256sum\ntar\ndd", "mtd0: 00800000 00010000"]
        with self.assertRaises(DeviceError): self.installer.inspect()
        self.assertEqual(self.transport.run.call_count,2)
        self.assertFalse(any("mkdir" in call.args[0] for call in self.transport.run.call_args_list))

    def test_foreign_boot_hook_is_preserved(self):
        self.transport.run.side_effect=["base64 sha256sum tar dd", "\n".join(f"mtd{i}: {n:08x} 00010000" for i,n in enumerate(PARTITION_SIZES))]
        self.installer.read=Mock(return_value=b"#!/bin/sh\nother_project")
        with self.assertRaisesRegex(DeviceError,"another boot modification"): self.installer.inspect()
        self.assertEqual(self.transport.run.call_count,2)

    def test_interrupted_base64_is_rejected(self):
        self.transport.run.return_value="truncated transfer"
        with self.assertRaises(DeviceError): self.installer.read("cat /dev/mtd0",maximum=100)

    def test_binary_backup_transfer_is_exact(self):
        data=bytes(range(256))*20
        def answer(command,**kwargs):
            marker=re.search(r"PFL_DATA_[0-9a-f]+",command)[0]
            return "\n"+marker+"_BEGIN\n"+base64.b64encode(data).decode()+"\n"+marker+"_END\n"
        self.transport.run.side_effect=answer
        self.assertEqual(self.installer.read("cat file",maximum=len(data)),data)
        with self.assertRaises(DeviceError): self.installer.read("cat file",maximum=100)

    def test_failed_upload_never_renames_destination(self):
        self.transport.run.return_value="wrong hash"
        with self.assertRaises(DeviceError):self.installer.upload("/run/test",b"data")
        self.assertFalse(any("mv -f" in call.args[0] for call in self.transport.run.call_args_list))

    def test_two_matching_full_backups_required(self):
        self.installer.details={"model":"synthetic"}
        self.installer.read=Mock(side_effect=[b"a"*FLASH_SIZE,b"b"*FLASH_SIZE])
        with self.assertRaisesRegex(DeviceError,"differ"):self.installer.backup(self.directory/"backups")
        self.transport.run.assert_not_called()

    def test_truncated_backup_stops_before_installation(self):
        self.installer.details={"model":"synthetic"};self.installer.read=Mock(return_value=b"short")
        with self.assertRaises(DeviceError):self.installer.backup(self.directory/"backups")
        self.transport.run.assert_not_called()

    def test_matching_backups_are_private_and_hashed(self):
        self.installer.details={"model":"synthetic"}
        data=b"a"*FLASH_SIZE
        self.installer.read=Mock(side_effect=[data,data,b"0"*2048])
        folder=self.installer.backup(self.directory/"backups")
        metadata=json.loads((folder/"backup.json").read_text())
        self.assertEqual(metadata["files"]["flash-read-1.bin"],hashlib.sha256(data).hexdigest())
        if sys.platform!="win32":self.assertEqual((folder/"flash-read-1.bin").stat().st_mode&0o777,0o600)

    def test_rollback_never_rewinds_operations_or_writes_flash(self):
        script=self.installer._rollback_script("/run/test-transaction")
        for forbidden in ("operations.dat","/dev/mtd","api.token","POST","schedules"):
            self.assertNotIn(forbidden,script)
        self.assertIn("active.rollback",script)
        self.assertIn("was-enabled",script)

    def test_restore_does_not_require_a_working_api(self):
        self.installer.inspect=Mock()
        self.installer.restore()
        self.installer.inspect.assert_called_once_with(require_api=False)
        self.assertIn("uninstall.sh",self.transport.run.call_args.args[0])

    def test_recovery_is_armed_before_boot_pointer_changes(self):
        self.installer.inspect=Mock(return_value={"model":"synthetic","identity":"synthetic"})
        self.installer.backup=Mock(return_value=self.directory)
        writes=[]
        self.transport.run.side_effect=lambda command,**kwargs:writes.append(command) or ""
        def upload(path,data):
            writes.append(path)
            if path.endswith("/boot.sh"):raise DeviceError("test interruption")
        self.installer.upload=upload
        with self.assertRaises(DeviceError):self.installer.install(self.directory)
        timer=next(i for i,x in enumerate(writes) if "sleep 180" in x)
        boot=next(i for i,x in enumerate(writes) if x.endswith("/boot.sh"))
        self.assertLess(timer,boot)
        self.assertIn("rollback.sh",writes[-1])

    def test_api_bypasses_proxies_and_bounds_its_response(self):
        from pet_feeder_installer.device import device_api
        with patch("pet_feeder_installer.device.build_opener") as build:
            response=build.return_value.open.return_value.__enter__.return_value
            response.read.return_value=b'{"api_version":1}'
            self.assertEqual(device_api("192.168.1.123","synthetic-token","info"),{"api_version":1})
            self.assertEqual(build.call_args.args[1].proxies,{})
            response.read.assert_called_once_with(8193)
            response.read.return_value=b"x"*8193
            with self.assertRaises(DeviceError):device_api("192.168.1.123","synthetic-token","info")

    def test_long_console_command_is_rejected_before_send(self):
        transport=object.__new__(Telnet);transport.socket=Mock()
        with self.assertRaises(DeviceError):transport.run("x"*2000)
        transport.socket.sendall.assert_not_called()

    def test_failed_api_activation_runs_rollback_without_feeding(self):
        self.installer.inspect=Mock(return_value={"model":"synthetic","identity":"synthetic"})
        self.installer.backup=Mock(return_value=self.directory)
        self.installer.upload=Mock()
        self.transport.run.return_value=""
        with patch("pet_feeder_installer.device.device_api",side_effect=ConnectionError), \
             patch("pet_feeder_installer.device.time.monotonic",side_effect=[0,1,100]), \
             patch("pet_feeder_installer.device.time.sleep"):
            with self.assertRaisesRegex(DeviceError,"did not start"):self.installer.install(self.directory)
        commands=[call.args[0] for call in self.transport.run.call_args_list]
        self.assertIn("rollback.sh",commands[-1])
        self.assertFalse(any("POST" in command or "/dev/mtd" in command for command in commands))

    def test_telnet_negotiation_can_be_split_across_packets(self):
        transport=object.__new__(Telnet);transport.socket=Mock();transport._partial=b""
        self.assertEqual(transport._clean(b"a\xff\xfd"),b"a")
        self.assertEqual(transport._clean(b"\x01b\xff\xff"),b"b\xff")
        transport.socket.sendall.assert_called_with(b"\xff\xfc\x01")


class WizardSecurityTests(unittest.TestCase):
    def setUp(self):
        self.wizard=Wizard(None,Path("unused"),demo=True)
        self.server=make_server(self.wizard)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.origin=f"http://127.0.0.1:{self.server.server_port}"
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.wizard.executor.shutdown()
    def test_status_requires_csrf_and_is_not_cached(self):
        with self.assertRaises(HTTPError):urlopen(self.origin+"/status")
        with urlopen(Request(self.origin+"/status",headers={"X-PFL-CSRF":self.wizard.csrf})) as response:
            self.assertEqual(response.headers["Cache-Control"],"no-store")
            self.assertEqual(json.load(response)["stage"],"welcome")
    def test_cross_origin_install_is_rejected(self):
        request=Request(self.origin+"/install",data=b"{}",headers={"X-PFL-CSRF":self.wizard.csrf,"Origin":"https://example.com"})
        with self.assertRaises(HTTPError) as context:urlopen(request)
        self.assertEqual(context.exception.code,403)
        self.assertFalse(self.wizard.busy)
    def test_dns_rebinding_host_is_rejected(self):
        request=Request(self.origin+"/",headers={"Host":"evil.example"})
        with self.assertRaises(HTTPError) as context:urlopen(request)
        self.assertEqual(context.exception.code,403)
    def test_cannot_install_without_review(self):
        with self.assertRaises(DeviceError):self.wizard.submit("install",{})
    def test_close_requires_csrf(self):
        request=Request(self.origin+"/quit",data=b"{}",headers={"Origin":self.origin})
        with self.assertRaises(HTTPError) as context:urlopen(request)
        self.assertEqual(context.exception.code,403)
        context.exception.close()

    def test_close_refuses_an_active_operation(self):
        self.wizard.busy=True
        request=Request(self.origin+"/quit",data=b"{}",headers={"X-PFL-CSRF":self.wizard.csrf,"Origin":self.origin})
        with self.assertRaises(HTTPError) as context:urlopen(request)
        self.assertEqual(context.exception.code,400)
        context.exception.close()

    def test_close_stops_the_idle_loopback_server(self):
        request=Request(self.origin+"/quit",data=b"{}",headers={"X-PFL-CSRF":self.wizard.csrf,"Origin":self.origin})
        with urlopen(request) as response:self.assertEqual(json.load(response),{"stopped":True})
        self.thread.join(timeout=3)
        self.assertFalse(self.thread.is_alive())

    def test_demo_never_connects_to_a_device(self):
        with patch("pet_feeder_installer.wizard.Telnet") as transport:
            self.wizard.run("inspect",{"address":"192.168.1.123"})
            self.assertEqual(self.wizard.status["stage"],"review")
            transport.assert_not_called()

    def test_local_startup_does_not_require_dns(self):
        with patch("socket.getfqdn", side_effect=AssertionError("DNS is unavailable")):
            server=make_server(self.wizard)
            try:
                self.assertEqual(server.server_name,"127.0.0.1")
                self.assertGreater(server.server_port,0)
            finally:
                server.server_close()

if __name__=="__main__":unittest.main()
