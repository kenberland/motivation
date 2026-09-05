#!/usr/bin/env python3
"""CGI endpoint that records movement events into a SQLite database.

Accepts a JSON POST body validated against a strict JSON Schema: the body
must contain exactly the required properties, with no missing or extra keys.
"""

import json
import sqlite3
import sys
import uuid

from jsonschema import Draft202012Validator

DB_PATH = "/var/www/motivation-data/motivation.sql"

SCHEMA = {
    "type": "object",
    "properties": {
        "event_id": {"type": "string", "minLength": 1},
        "created_at": {"type": "string", "pattern": r"^[0-9]+$"},
        "name": {"type": "string", "minLength": 1},
        "movement_type": {"enum": ["enter", "exit"]},
    },
    "required": ["event_id", "created_at", "name", "movement_type"],
    "additionalProperties": False,
}

VALIDATOR = Draft202012Validator(SCHEMA)


def respond(status, payload):
    sys.stdout.write(f"Status: {status}\r\n")
    sys.stdout.write("Content-Type: application/json\r\n\r\n")
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.exit(0)


def fail(message):
    respond("400 Bad Request", {"result": "error", "message": message})


def main():
    raw = sys.stdin.buffer.read()

    try:
        body = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON: {exc}")

    errors = sorted(VALIDATOR.iter_errors(body), key=lambda e: e.path)
    if errors:
        fail("; ".join(e.message for e in errors))

    event_id = body["event_id"]
    created_at = int(body["created_at"])
    name = body["name"]
    movement_type = body["movement_type"]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS movement ("
            "event_id TEXT PRIMARY KEY, "
            "created_at INTEGER NOT NULL, "
            "name TEXT NOT NULL, "
            "movement_type TEXT NOT NULL)"
        )
        conn.execute(
            "INSERT OR REPLACE INTO movement "
            "(event_id, created_at, name, movement_type) VALUES (?, ?, ?, ?)",
            (event_id, created_at, name, movement_type),
        )
        conn.commit()
    finally:
        conn.close()

    respond("200 OK", {"result": "success", "event-id": event_id})


if __name__ == "__main__":
    main()
