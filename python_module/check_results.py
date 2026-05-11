import csv
from pathlib import Path

RESULTS_FILE = "results/output.csv"

# Actions from RTL
ACTION_DROP   = 0
ACTION_ACCEPT = 1
ACTION_REJECT = 2

# Flags from RTL
FLAG_NONE      = 0
FLAG_SEQ_GAP   = 1
FLAG_RISK_FAIL = 2
FLAG_SYMBOL    = 4

# Expected behavior for each packet
expected = {
    0: (ACTION_ACCEPT, FLAG_NONE),
    1: (ACTION_ACCEPT, FLAG_NONE),
    2: (ACTION_DROP,   FLAG_SYMBOL),
    3: (ACTION_ACCEPT, FLAG_SEQ_GAP),
    4: (ACTION_ACCEPT, FLAG_NONE),
    5: (ACTION_REJECT, FLAG_RISK_FAIL),
}

def main():
    results_path = Path(RESULTS_FILE)

    if not results_path.exists():
        print(f"ERROR: Missing {RESULTS_FILE}")
        raise SystemExit(1)

    seen_packets = set()
    overall_pass = True

    with open(results_path, "r") as f:
        reader = csv.DictReader(f)

        for row in reader:
            packet_id = int(row["packet_id"])

            created_cycle = int(row["created_cycle"])
            submitted_cycle = int(row["submitted_cycle"])
            output_cycle = int(row["output_cycle"])

            action = int(row["action"])
            flags = int(row["flags"])

            latency_from_created = int(row["latency_from_created"])
            latency_from_submitted = int(row["latency_from_submitted"])

            seen_packets.add(packet_id)

            if packet_id not in expected:
                print(f"FAIL: unexpected packet_id {packet_id}")
                overall_pass = False
                continue

            expected_action, expected_flags = expected[packet_id]

            packet_pass = True

            # Check action
            if action != expected_action:
                print(
                    f"FAIL packet {packet_id}: "
                    f"expected action={expected_action}, got {action}"
                )
                packet_pass = False

            # Check flags
            if flags != expected_flags:
                print(
                    f"FAIL packet {packet_id}: "
                    f"expected flags={expected_flags}, got {flags}"
                )
                packet_pass = False

            # Check latency
            if latency_from_created < 1:
                print(
                    f"FAIL packet {packet_id}: "
                    f"latency_from_created < 1"
                )
                packet_pass = False

            if latency_from_submitted < 0:
                print(
                    f"FAIL packet {packet_id}: "
                    f"latency_from_submitted < 0"
                )
                packet_pass = False

            if output_cycle < submitted_cycle:
                print(
                    f"FAIL packet {packet_id}: "
                    f"output_cycle before submitted_cycle"
                )
                packet_pass = False

            if packet_pass:
                print(
                    f"PASS packet {packet_id}: "
                    f"action={action}, "
                    f"flags={flags}, "
                    f"created={created_cycle}, "
                    f"submitted={submitted_cycle}, "
                    f"output={output_cycle}, "
                    f"latency_created={latency_from_created}, "
                    f"latency_submitted={latency_from_submitted}"
                )
            else:
                overall_pass = False

    # Check all expected packets appeared
    missing = set(expected.keys()) - seen_packets

    if missing:
        print(f"FAIL: missing packets {sorted(missing)}")
        overall_pass = False

    extra = seen_packets - set(expected.keys())

    if extra:
        print(f"FAIL: unexpected packets present {sorted(extra)}")
        overall_pass = False

    print("\n==============================")

    if overall_pass:
        print("ALL CHECKS PASSED")
    else:
        print("CHECKS FAILED")
        raise SystemExit(1)

if __name__ == "__main__":
    main()