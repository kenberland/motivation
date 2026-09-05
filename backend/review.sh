#!/usr/bin/env python3
"""CGI endpoint that renders recent movement events in an HTML table.

Data is read from SQLite and embedded into the page as JSON. Rendering,
pagination (configurable page size with previous/next buttons), and sorting
are handled client-side by TanStack Table loaded from a public CDN.
"""

import json
import os
import sqlite3
import sys
from urllib.parse import parse_qs

DB_PATH = "/var/www/motivation-data/motivation.sql"


def read_events():
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS movement ("
            "event_id TEXT PRIMARY KEY, "
            "created_at INTEGER NOT NULL, "
            "name TEXT NOT NULL, "
            "movement_type TEXT NOT NULL)"
        )
        rows = conn.execute(
            "SELECT event_id, created_at, name, movement_type "
            "FROM movement ORDER BY created_at DESC"
        ).fetchall()
    finally:
        conn.close()

    return [
        {
            "event_id": r[0],
            "created_at": r[1],
            "name": r[2],
            "movement_type": r[3],
        }
        for r in rows
    ]


PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Movement Events</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 2rem; color: #222; }
  h1 { font-size: 1.4rem; }
  table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
  th, td { border: 1px solid #ddd; padding: 0.5rem 0.75rem; text-align: left; }
  th { background: #f5f5f5; cursor: pointer; user-select: none; }
  tr:nth-child(even) td { background: #fafafa; }
  .controls { margin-top: 1rem; display: flex; gap: 0.75rem; align-items: center; }
  button { padding: 0.35rem 0.9rem; cursor: pointer; }
  button:disabled { opacity: 0.4; cursor: default; }
  label { margin-left: auto; }
</style>
</head>
<body>
<h1>Movement Events</h1>
<table id="tbl">
  <thead></thead>
  <tbody></tbody>
</table>
<div class="controls">
  <button id="prev">Previous</button>
  <button id="next">Next</button>
  <span id="pageinfo"></span>
  <label>Time zone:
    <select id="tz">
      <option value="America/Los_Angeles">Pacific (Los Angeles)</option>
      <option value="America/Denver">Mountain (Denver)</option>
      <option value="America/Phoenix">Mountain no DST (Phoenix)</option>
      <option value="America/Chicago">Central (Chicago)</option>
      <option value="America/New_York">Eastern (New York)</option>
      <option value="America/Anchorage">Alaska (Anchorage)</option>
      <option value="Pacific/Honolulu">Hawaii (Honolulu)</option>
      <option value="UTC">UTC</option>
    </select>
  </label>
  <label>Page size:
    <select id="pagesize">
      <option>10</option>
      <option>25</option>
      <option>50</option>
      <option>100</option>
    </select>
  </label>
</div>

<script type="module">
import {
  createTable,
  getCoreRowModel,
  getPaginationRowModel,
  getSortedRowModel,
} from 'https://esm.sh/@tanstack/table-core@8';

const DATA = __DATA__;
const DEFAULT_N = __N__;

let currentTZ = 'America/Los_Angeles';

function formatCell(columnId, value) {
  if (columnId === 'created_at') {
    return new Intl.DateTimeFormat('en-US', {
      timeZone: currentTZ,
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
      hour12: false, timeZoneName: 'short',
    }).format(new Date(value * 1000));
  }
  return value;
}

const columns = [
  { accessorKey: 'created_at', header: 'Time' },
  { accessorKey: 'name', header: 'Name' },
  { accessorKey: 'movement_type', header: 'Movement' },
  { accessorKey: 'event_id', header: 'Event ID' },
];

let table;
let state;

table = createTable({
  data: DATA,
  columns,
  initialState: {
    pagination: { pageIndex: 0, pageSize: DEFAULT_N },
    sorting: [{ id: 'created_at', desc: true }],
  },
  state: {},
  onStateChange: updater => {
    state = typeof updater === 'function' ? updater(state) : updater;
    table.setOptions(prev => ({ ...prev, state }));
    render();
  },
  getCoreRowModel: getCoreRowModel(),
  getPaginationRowModel: getPaginationRowModel(),
  getSortedRowModel: getSortedRowModel(),
});

// Seed our controlled state with the table's fully-populated defaults
// (columnPinning, columnVisibility, etc.) so no state slice is undefined.
state = { ...table.initialState };
table.setOptions(prev => ({ ...prev, state }));

const thead = document.querySelector('#tbl thead');
const tbody = document.querySelector('#tbl tbody');
const pageinfo = document.getElementById('pageinfo');

function render() {
  thead.innerHTML = '';
  const hr = document.createElement('tr');
  table.getHeaderGroups()[0].headers.forEach(h => {
    const th = document.createElement('th');
    const dir = h.column.getIsSorted();
    th.textContent = h.column.columnDef.header + (dir === 'asc' ? ' ▲' : dir === 'desc' ? ' ▼' : '');
    th.onclick = () => h.column.toggleSorting();
    hr.appendChild(th);
  });
  thead.appendChild(hr);

  tbody.innerHTML = '';
  table.getRowModel().rows.forEach(row => {
    const tr = document.createElement('tr');
    row.getVisibleCells().forEach(cell => {
      const td = document.createElement('td');
      td.textContent = formatCell(cell.column.id, cell.getValue());
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });

  const pi = table.getState().pagination.pageIndex;
  const pc = table.getPageCount();
  pageinfo.textContent = pc ? `Page ${pi + 1} of ${pc} (${DATA.length} events)` : 'No events';
  document.getElementById('prev').disabled = !table.getCanPreviousPage();
  document.getElementById('next').disabled = !table.getCanNextPage();
}

document.getElementById('prev').onclick = () => table.previousPage();
document.getElementById('next').onclick = () => table.nextPage();
const sizeSel = document.getElementById('pagesize');
sizeSel.value = String(DEFAULT_N);
sizeSel.onchange = e => table.setPageSize(Number(e.target.value));

const tzSel = document.getElementById('tz');
tzSel.value = currentTZ;
tzSel.onchange = e => { currentTZ = e.target.value; render(); };

render();
</script>
</body>
</html>
"""


def main():
    qs = parse_qs(os.environ.get("QUERY_STRING", ""))
    try:
        n = int(qs.get("n", ["10"])[0])
    except (ValueError, IndexError):
        n = 10
    n = max(1, min(n, 500))

    events = read_events()

    html = PAGE.replace("__DATA__", json.dumps(events)).replace("__N__", str(n))

    sys.stdout.write("Content-Type: text/html; charset=utf-8\r\n\r\n")
    sys.stdout.write(html)


if __name__ == "__main__":
    main()
