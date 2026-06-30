# Template Authoring Guide

Templates are normal `.xlsx` files. Edit them in Microsoft Excel — no
proprietary designer tool. The renderer only reads/copies what is already
in the workbook: fonts, borders, fills, number formats, alignment, merged
cells. **It never invents styling.**

## Report JSON structure

A report submission is a single JSON document with six top-level fields:

```json
{
  "report": { "id": "INV-2026-0001", "title": "Monthly Hospital Report", "version": "1.0",
              "created_at": "2026-06-01T08:00:00Z", "generated_by": "billing-service",
              "locale": "en-US", "timezone": "UTC" },
  "metadata": { "company": { "name": "..." }, "logo": null, "period": {}, "parameters": {} },
  "template_id": "hospital_report",
  "output_format": "xlsx",
  "report_id": "your-own-tracking-id",
  "sheets": [ ... ]
}
```

| Field | Required | Purpose |
|---|---|---|
| `report.id` | No | **Your own** reference number for this *document*, for display only (e.g. `{{report.id}}` printed on the report). Never used for tracking — see below. |
| `report.title` / `.version` / `.created_at` / `.generated_by` / `.locale` / `.timezone` | No | Free-form, available as `{{report.title}}` etc. anywhere in the template. |
| `metadata` | No | Free-form (`company`, `logo`, `period`, `parameters`, or anything else) — available as `{{metadata.x.y}}`. |
| `template_id` | Yes | The id (or name) of a previously uploaded template — see `POST /templates`. |
| `output_format` | No (default `xlsx`) | `xlsx`, `pdf`, or `html`. |
| `report_id` (top-level) | No | Caller-supplied **tracking** id — see below. |
| `sheets` | Yes | Array of sheet objects — see Sheets and sections below. |

There are two unrelated-looking `id`s here on purpose — know which is which:

- **`report.id`** (nested inside `report`) is purely cosmetic — it exists
  only so a value you choose can appear inside the rendered output via
  `{{report.id}}`. It is never read for anything else.
- **Top-level `report_id`** is the *tracking* id — the same id
  `POST /reports` returns and `GET /reports/{report_id}` polls on. If you
  omit it, the engine generates one (UUIDv7) and returns it in the
  response, same as always. If you supply it, the engine uses **your**
  value as the tracking id instead of generating its own — submitting the
  same `report_id` again once the render has **completed** (SUCCESS or FAILED) **re-renders** from scratch with the new payload — useful for "update data, regenerate the same report" flows. Submitting while the previous render is still in progress (QUEUED or PROCESSING) returns `409`.

This matters if your own backend needs to start tracking a report job
*before* it can call this engine — e.g. you're fetching/aggregating data
from your own database first (a process this engine has no visibility
into), and want to hand a job id back to your own frontend immediately so
it can start polling, rather than waiting for your data fetch to finish.
Mint the id yourself (e.g. a UUID) up front, return it to your caller,
track your own "fetching data" phase under that id on your side, then
include it as `report_id` when you finally call `POST /reports` once the
data is ready. From that point on, `GET /reports/{report_id}` against
*this* engine answers with the real render status — using the exact same
id throughout, with no separate mapping table needed between "your job
id" and "the engine's job id." (The engine genuinely cannot know
anything about a report before `POST /reports` is called — there's no way
around tracking the pre-submission phase yourself, but at least it's one
id, not two.)

## Scalar placeholders

Anywhere in any cell: `{{report.title}}`, `{{metadata.company.name}}`,
`{{metadata.period.from}}`, `{{metadata.parameters.branch}}`.

- Unknown placeholder → left blank.
- Missing JSON field → left blank.
- Never throws.
- A cell containing *only* one placeholder (e.g. `{{row.total}}`) keeps the
  resolved value's native type (number, date) so Excel number formats still
  apply. A cell mixing text and placeholders (e.g. `Total: {{row.total}}`)
  is always rendered as a string.

## TABLE component

```
{{TABLE:patient}}          <- start marker, own cell
Patient | Bed | Diagnosis  <- header row, static
{{ROW}}{{row.name}} | {{row.bed}} | {{row.diagnosis}}   <- exactly one template row
                 Grand Total | {{summary.total_charges}} <- footer row(s), static + summary placeholders
{{ENDTABLE}}                <- end marker, own cell
```

- `{{ROW}}` marks which row is the repeating template row. It must appear
  in the **same cell** as that row's first column value, prefixed:
  `{{ROW}}{{row.name}}`. (The `{{ROW}}` portion resolves to blank and is
  discarded — only `{{row.name}}` survives in the output.)
- Every other cell in the template row uses `{{row.<field>}}` to reference
  a field on the current JSON row object.
- Footer cells use `{{summary.<key>}}` to reference `component.summary.values`.
  No calculation happens here — the caller must have already computed totals.
- The renderer duplicates the template row once per JSON row, copies its
  style to every new row, and pushes the footer down automatically.
- If `rows` is empty, the template row is cleared (left blank) and the
  section collapses unless `visible_if_empty` is true.

## MATRIX component

A dynamic crosstab built from flat JSON rows (`row_field`, `column_field`,
`value_field`, `aggregate`). The renderer computes row/column keys and
totals; the template only supplies five **style-donor** cells:

```
{{MATRIX:bed}}
{{MATRIX:bed:CORNER}}   {{MATRIX:bed:COLHEADER}}
{{MATRIX:bed:ROWHEADER}} {{MATRIX:bed:DATA}}

                                    {{MATRIX:bed:TOTAL}}
{{ENDMATRIX}}
```

- `CORNER` — style for the top-left cell (becomes blank in the output).
- `COLHEADER` / `ROWHEADER` — style for the generated column/row header cells.
- `DATA` — style for the aggregated value cells.
- `TOTAL` — style for the row-total column, column-total row, and grand total.
- The grid expands **down and right of the corner cell** — leave that area
  empty in the template; row/column counts are data-driven.
- `aggregate`: `SUM`, `COUNT`, `AVG`, `MIN`, `MAX`.
- `sort`: `ascending`, `descending`, or `custom` (with `custom_order: [...]`
  — any keys not listed are appended after, sorted ascending).

## KEY_VALUE component

```
{{KEYVALUE:summary}}
{{LABEL}}   {{VALUE}}     <- exactly one template row
{{ENDKEYVALUE}}
```

One row per JSON `items` entry, label/value duplicated like a table's
template row. Style is copied from the template row each time.

## Stacking multiple components on one sheet

TABLE and KEY_VALUE both duplicate their template row in place and shift
everything below them down by the same amount — so whatever spacing
exists in the template between one component and the next is always
preserved exactly, whether that's a blank spacer row or no gap at all
(the next marker directly below). You never need to plan for this; it
just works regardless of how many rows either component ends up
inserting.

**MATRIX is different — it does not shift anything below it.** Its grid
just expands in place from the corner cell. If your data produces a
bigger grid than the blank space you left in the template, it **silently
overwrites** whatever comes next (the next component's markers included)
instead of pushing it down. Always leave enough blank rows/columns below
and to the right of a MATRIX's corner cell for the largest grid your data
could realistically produce, especially if something else follows it on
the same sheet.

## Multi-line cell text

A `{{row.<field>}}` value containing `\n` renders with the line breaks
intact in every output format. To have it actually *display* as multiple
visible lines rather than one flattened line, set **Wrap Text** on that
template cell in Excel (Format Cells → Alignment → Wrap text) — this is
an Excel cell setting, not something the engine turns on for you. Row
height does not need to be set manually; leave it on "auto" and Excel/the
PDF/HTML renderer sizes the row to fit the wrapped content.

## Images

A picture inserted directly into the template (Excel → Insert → Picture)
passes through untouched, including across a TABLE/KEY_VALUE row
insertion elsewhere on the same sheet. There is no JSON-driven dynamic
image component (e.g. "insert this URL as a logo") — only static images
already embedded in the template by you survive. Anchor images outside
the area a TABLE's template row or a MATRIX's grid will expand into,
since cell insertion does not reposition floating images, and a MATRIX's
silent-overwrite behavior (above) applies to images sitting in that
overwritten area too.

## Output formats

`output_format` in the request: `xlsx` (default), `pdf`, or `html`. PDF
and HTML are always a conversion of the same rendered `.xlsx` — never a
different template, so nothing about the template needs to change to get
either. A few format-specific notes:

- **PDF** respects the template's Excel Page Layout settings (paper size,
  orientation, margins, scaling) exactly as configured — see Page size,
  orientation, and print fields below.
- **HTML** has no concept of pages, so anything that is a page-layout
  feature in Excel — headers/footers, page numbers, paper size/orientation
  — does **not** appear in HTML output. It's a flat scrollable rendering
  of the sheet's cells only.
- Images embedded in the template appear correctly in both PDF (embedded
  in the PDF itself) and HTML (inlined as part of the single `.html` file
  — no separate image files to manage).

## Headers & footers

Excel's own Page Layout → Header & Footer feature is preserved as-is —
including `{{...}}` placeholders typed into it, which resolve the same as
anywhere else in the template. Excel's print model supports these
repeat scopes:

| Scope | How to set it in Excel | Notes |
|---|---|---|
| All pages | Just set the header/footer text — no special option needed | Default scope if you don't enable the options below |
| First page only | Page Setup → Header/Footer → check "Different first page" | Set the *first page's own* header/footer text — it does not fall back to the "all pages" text if left blank |
| Odd pages | Page Setup → Header/Footer → check "Different odd and even pages" → set the odd-page text | |
| Even pages | Same checkbox → set the even-page text | |

**There is no "last page only" scope.** Excel's page-setup model has no
such concept — pagination itself is only known at print/PDF-export time,
not when the template is authored, so nothing (this engine or Excel
itself) can target "whichever page turns out to be last." If you need
something that only appears at the end of a report, put it in the
TABLE's footer rows instead (see TABLE component above) — that's
content-based, not page-based, so it works regardless of pagination.

Header/footer placeholders only have access to `{{report.*}}` and
`{{metadata.*}}` — not `{{row.*}}` or `{{summary.*}}`, since those only
make sense inside a specific table's data.

## Page numbers, dates, and other print-time variables

These are **native Excel field codes**, typed directly into a
header/footer box — not `{{}}` placeholders, and not something this
engine computes (pagination depends on paper size, margins, font size,
and content, which only Excel/the PDF renderer knows at render time):

| Code | Meaning |
|---|---|
| `&P` | Current page number |
| `&N` | Total page count |
| `&D` | Current date |
| `&T` | Current time |
| `&A` | Sheet (tab) name |
| `&F` | File name |

Example footer text: `Page &P of &N` → renders as `Page 1 of 3`, `Page 2
of 3`, etc., correctly per page in both Excel and PDF export. **These do
not appear in HTML output** (no pagination concept — see Output formats
above).

## Page size, orientation, and print fields

Paper size and orientation (Page Layout → Size / Orientation) are never
touched by the engine — whatever the template specifies carries through
to PDF unchanged. If the template leaves them unset, the PDF converter
falls back to its own default, which is **not guaranteed to be any
particular size** (it can vary by installation). If a specific paper size
or orientation matters for your use case, set it explicitly in the
template — don't rely on a fallback.

## Sheets and sections

- A `Sheet` not marked `visible` in its JSON metadata is removed entirely
  from the output workbook.
- A `Section` collapses (its components are still rendered into the sheet,
  but contribute no content) when every component inside it has no data —
  unless `visible_if_empty: true`.
- Map a JSON sheet to a template tab via `template_sheet` (defaults to the
  JSON `name` if omitted) — this is the worksheet tab name in the `.xlsx`,
  not a display label.

## What you cannot do in a template

- No live Excel formulas computed by the engine — Excel recalculates
  formulas itself when the file is opened; the engine never evaluates them.
- No nested/repeating sections inside a TABLE template row beyond simple
  `{{row.<field>}}` substitution.
- No JSON-driven dynamic images, charts, QR codes, or barcodes — only
  static images already embedded in the template by you survive (see
  Images above). A component that generates one of these *from* JSON data
  doesn't exist yet.
- No "last page only" header/footer scope, and no header/footer/page
  number/paper size support in HTML output (see Headers & footers and
  Output formats above) — both are inherent to Excel's page model having
  no equivalent in a pageless HTML view.
