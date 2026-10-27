import importlib.machinery
import importlib.util
import json
import pathlib
import unittest

HELPER = pathlib.Path(__file__).resolve().parents[2] / "plugin" / "fprint-helper"
loader = importlib.machinery.SourceFileLoader("fprint_helper", str(HELPER))
spec = importlib.util.spec_from_loader("fprint_helper", loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)

DEVICE = "/net/reactivated/Fprint/Device/0"
PROPS = {"name": "Test Reader", "scan-type": "press", "num-enroll-stages": 3}


class FakeBus:
    """Answers at once, from per-method replies; records every call."""

    def __init__(self):
        self.calls = []
        self.errors = {}
        self.enrolled = ["right-index-finger"]
        self.handler = None
        self.held = {}

    def call(self, path, iface, method, signature, args, timeout_ms, callback):
        self.calls.append((method, args))
        if method in self.held:
            self.held[method].append(callback)
            return
        if method in self.errors:
            callback(self.errors[method], None)
            return
        replies = {
            "GetDefaultDevice": (DEVICE,),
            "GetAll": (PROPS,),
            "ListEnrolledFingers": (list(self.enrolled),),
        }
        callback(None, replies.get(method, ()))

    def subscribe(self, path, handler):
        self.handler = handler

    def methods(self):
        return [m for m, _ in self.calls]


class FakeTimers:
    def __init__(self):
        self.pending = {}
        self.next = 0

    def add(self, seconds, fn):
        self.next += 1
        self.pending[self.next] = fn
        return self.next

    def remove(self, handle):
        self.pending.pop(handle, None)

    def fire_all(self):
        for handle in list(self.pending):
            self.pending.pop(handle)()


class SessionTest(unittest.TestCase):
    def setUp(self):
        self.bus = FakeBus()
        self.timers = FakeTimers()
        self.events = []
        self.session = helper.Session(self.bus, self.events.append, self.timers)

    def send(self, **command):
        self.session.handle_line(json.dumps(command))

    def of_type(self, kind):
        return [e for e in self.events if e["type"] == kind]

    def refreshed(self):
        self.send(cmd="refresh")
        self.events.clear()
        self.bus.calls.clear()

    def test_refresh_reports_device_and_prints(self):
        self.send(cmd="refresh")
        self.assertEqual(self.events, [{
            "type": "state", "available": True,
            "device": {"name": "Test Reader", "scanType": "press", "stages": 3},
            "enrolled": ["right-index-finger"],
        }])

    def test_no_prints_is_an_empty_list(self):
        self.bus.errors["ListEnrolledFingers"] = "net.reactivated.Fprint.Error.NoEnrolledPrints"
        self.send(cmd="refresh")
        self.assertEqual(self.events[-1]["enrolled"], [])

    def test_missing_service_and_reader(self):
        self.bus.errors["GetDefaultDevice"] = "org.freedesktop.DBus.Error.ServiceUnknown"
        self.send(cmd="refresh")
        self.assertEqual(self.events[-1], {"type": "state", "available": False, "reason": "no-service"})
        self.bus.errors["GetDefaultDevice"] = "net.reactivated.Fprint.Error.NoSuchDevice"
        self.send(cmd="refresh")
        self.assertEqual(self.events[-1]["reason"], "no-device")

    def test_enroll_counts_stages_then_releases_and_rereads(self):
        self.refreshed()
        self.send(cmd="enroll", finger="left-thumb")
        self.assertEqual(self.bus.methods(), ["Claim", "EnrollStart"])
        self.assertEqual(self.bus.calls[1][1], ("left-thumb",))
        self.bus.handler("EnrollStatus", ("enroll-stage-passed", False))
        self.bus.handler("EnrollStatus", ("enroll-retry-scan", False))
        self.bus.handler("EnrollStatus", ("enroll-stage-passed", False))
        self.bus.enrolled.append("left-thumb")
        self.bus.handler("EnrollStatus", ("enroll-completed", True))
        enroll = self.of_type("enroll")
        self.assertEqual([(e["result"], e["stage"], e["total"]) for e in enroll], [
            ("enroll-started", 0, 3),
            ("enroll-stage-passed", 1, 3),
            ("enroll-retry-scan", 1, 3),
            ("enroll-stage-passed", 2, 3),
            ("enroll-completed", 2, 3),
        ])
        self.assertTrue(enroll[-1]["done"])
        self.assertEqual(self.bus.methods()[-3:], ["EnrollStop", "Release", "ListEnrolledFingers"])
        self.assertIn("left-thumb", self.events[-1]["enrolled"])
        self.assertIsNone(self.session.op)

    def test_unknown_finger_is_ignored(self):
        self.refreshed()
        self.send(cmd="enroll", finger="left-little-finger")
        self.send(cmd="delete", finger="../etc")
        self.assertEqual(self.bus.calls, [])

    def test_claim_error_maps_to_a_code(self):
        self.refreshed()
        self.bus.errors["Claim"] = "net.reactivated.Fprint.Error.AlreadyInUse"
        self.send(cmd="enroll", finger="left-thumb")
        self.assertEqual(self.of_type("error"), [{"type": "error", "op": "enroll", "code": "in-use"}])
        self.assertNotIn("EnrollStart", self.bus.methods())
        self.assertIsNone(self.session.op)

    def test_unknown_error_is_generic(self):
        self.assertEqual(helper.error_code("com.example.Weird"), "generic")
        self.assertEqual(helper.error_code(None), "generic")

    def test_cancel_stops_and_releases(self):
        self.refreshed()
        self.send(cmd="enroll", finger="left-thumb")
        self.send(cmd="cancel")
        self.assertEqual(self.bus.methods()[2:4], ["EnrollStop", "Release"])
        self.assertEqual(self.of_type("cancelled"), [{"type": "cancelled", "op": "enroll"}])
        # Late signals from the stopped scan change nothing.
        self.bus.handler("EnrollStatus", ("enroll-stage-passed", False))
        self.assertEqual(len(self.of_type("enroll")), 1)

    def test_claim_landing_after_cancel_releases(self):
        self.refreshed()
        pending = []
        self.bus.held["Claim"] = pending
        self.send(cmd="verify")
        self.send(cmd="cancel")
        del self.bus.held["Claim"]
        pending[0](None, ())
        self.assertEqual(self.bus.methods()[-2:], ["Release", "ListEnrolledFingers"])
        self.assertNotIn("VerifyStart", self.bus.methods())
        self.assertFalse(self.session.claimed)

    def test_verify_match_reports_the_finger(self):
        self.refreshed()
        self.send(cmd="verify")
        self.assertEqual(self.bus.calls[1], ("VerifyStart", ("any",)))
        self.bus.handler("VerifyFingerSelected", ("right-index-finger",))
        self.bus.handler("VerifyStatus", ("verify-match", True))
        last = self.of_type("verify")[-1]
        self.assertEqual((last["result"], last["finger"], last["done"]), ("verify-match", "right-index-finger", True))
        self.assertEqual(self.bus.methods()[-3:], ["VerifyStop", "Release", "ListEnrolledFingers"])
        self.assertEqual(self.timers.pending, {})

    def test_verify_retry_keeps_scanning(self):
        self.refreshed()
        self.send(cmd="verify")
        self.bus.handler("VerifyStatus", ("verify-retry-scan", False))
        self.assertEqual(self.session.op, "verify")
        self.bus.handler("VerifyStatus", ("verify-no-match", True))
        self.assertIsNone(self.session.op)
        self.assertEqual(self.of_type("verify")[-1]["finger"], "")

    def test_verify_times_out(self):
        self.refreshed()
        self.send(cmd="verify")
        self.timers.fire_all()
        self.assertEqual(self.of_type("verify")[-1]["result"], "verify-timeout")
        self.assertIn("VerifyStop", self.bus.methods())
        self.assertIsNone(self.session.op)

    def test_fprintd_restarting_mid_enroll_starts_over(self):
        self.refreshed()
        self.send(cmd="enroll", finger="left-thumb")
        self.bus.handler("EnrollStatus", ("enroll-stage-passed", False))
        self.session.service_lost()
        self.assertFalse(self.session.claimed)
        self.assertEqual(self.session.op, "enroll")
        self.timers.fire_all()
        self.assertEqual(self.bus.methods()[-2:], ["Claim", "EnrollStart"])
        last = self.of_type("enroll")[-1]
        self.assertEqual((last["result"], last["stage"]), ("enroll-started", 0))
        self.assertEqual(self.of_type("error"), [])

    def test_fprintd_lost_on_start_retries_then_gives_up(self):
        self.refreshed()
        self.bus.errors["VerifyStart"] = "org.freedesktop.DBus.Error.NoReply"
        self.send(cmd="verify")
        for _ in range(helper.MAX_RESTARTS):
            self.assertEqual(self.of_type("error"), [])
            self.timers.fire_all()
        self.assertEqual(self.bus.methods().count("VerifyStart"), helper.MAX_RESTARTS + 1)
        self.assertEqual(self.of_type("error"), [{"type": "error", "op": "verify", "code": "generic"}])
        self.assertIsNone(self.session.op)
        # A new attempt gets its own tries.
        del self.bus.errors["VerifyStart"]
        self.send(cmd="verify")
        self.assertEqual(self.session.restarts, 0)

    def test_cancel_while_waiting_for_fprintd(self):
        self.refreshed()
        self.send(cmd="verify")
        self.session.service_lost()
        self.send(cmd="cancel")
        self.assertEqual(self.timers.pending, {})
        self.assertNotIn("VerifyStop", self.bus.methods())
        self.assertEqual(self.of_type("cancelled"), [{"type": "cancelled", "op": "verify"}])

    def test_fprintd_leaving_while_idle_changes_nothing(self):
        self.refreshed()
        self.session.service_lost()
        self.assertEqual((self.bus.calls, self.events, self.timers.pending), ([], [], {}))

    def test_delete(self):
        self.refreshed()
        self.bus.enrolled = []
        self.send(cmd="delete", finger="right-index-finger")
        self.assertEqual(self.bus.methods(), ["Claim", "DeleteEnrolledFinger", "Release", "ListEnrolledFingers"])
        self.assertEqual(self.of_type("deleted"), [{"type": "deleted", "finger": "right-index-finger"}])
        self.assertEqual(self.events[-1]["enrolled"], [])

    def test_one_operation_at_a_time(self):
        self.refreshed()
        self.send(cmd="verify")
        self.send(cmd="enroll", finger="left-thumb")
        self.send(cmd="refresh")
        self.assertEqual(self.bus.methods(), ["Claim", "VerifyStart"])

    def test_shutdown_stops_without_rereading(self):
        self.refreshed()
        self.send(cmd="enroll", finger="left-thumb")
        self.session.shutdown()
        self.assertEqual(self.bus.methods()[-2:], ["EnrollStop", "Release"])
        self.assertEqual(self.of_type("state"), [])

    def test_invalid_input_is_ignored(self):
        self.session.handle_line("not json")
        self.session.handle_line("[1, 2]")
        self.session.handle_line("")
        self.assertEqual(self.bus.calls, [])


if __name__ == "__main__":
    unittest.main()
