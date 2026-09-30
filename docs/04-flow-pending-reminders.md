# 04 – Flow PR-03: Pending Purchase Reminders

**Trigger:** every weekday at 09:00 (your time zone)
**Result:**

* **Finance** gets one digest email listing every request in *Approved -
  Pending Purchase*, oldest first, showing how many days each has been
  waiting. If any request has waited `EscalateAfterDays` or more, the email
  is marked **High importance**, the overdue rows are highlighted, and the
  **CEO is copied**.
* Each listed request gets *Reminders Sent* +1 and *Last Reminder* = now, so
  the list shows how often Finance has been reminded.
* **The CEO** gets a separate nudge listing approvals waiting longer than
  `CEOReminderAfterDays`.
* Nothing is sent when there's nothing pending.

```
Recurrence (Mon–Fri 09:00)
├─ Initialize variables: CEOEmail, FinanceEmail, EscalateAfterDays, CEOReminderAfterDays
├─ Branch A – Finance
│   ├─ Get items        Get Pending Purchases      (Status = Approved - Pending Purchase)
│   └─ Condition        Any Pending?
│       └─ Yes: Filter array Overdue Purchases → Select Purchase Rows → Send email Finance Digest
│               → Apply to each: Update item (Reminders Sent +1, Last Reminder)
└─ Branch B – CEO (parallel)
    ├─ Get items        Get Stale Approvals        (Status = Pending CEO Approval, older than N days)
    └─ Condition        Any Stale?
        └─ Yes: Select Approval Rows → Send email CEO Nudge
```

## Build it

**Create → Scheduled cloud flow**, name it `PR-03 Pending Purchase Reminders`.

### 1. Recurrence

| Field | Value |
|---|---|
| Interval / Frequency | `1` / `Week` |
| Time zone | your time zone, e.g. *(UTC+05:30) Chennai, Kolkata, Mumbai, New Delhi* |
| On these days | Monday, Tuesday, Wednesday, Thursday, Friday |
| At these hours | `9` |
| At these minutes | `0` |

(For reminders every day, use Frequency `Day`. For twice a day, use hours `9,15`.)

### 2. Variables

| Name | Type | Value |
|---|---|---|
| `CEOEmail` | String | `ceo@yourorg.com` |
| `FinanceEmail` | String | `finance@yourorg.com` |
| `EscalateAfterDays` | Integer | `5` |
| `CEOReminderAfterDays` | Integer | `2` |

---

### Branch A – Finance digest

**A1. SharePoint *Get items* – rename to *Get Pending Purchases***

| Field | Value |
|---|---|
| Site Address / List Name | your site / `Purchase Requests` |
| Filter Query | `RequestStatus eq 'Approved - Pending Purchase'` |
| Order By | `DecisionDate asc` |
| Top Count | `500` |

**A2. Condition – *Any Pending?***

`@{length(outputs('Get_Pending_Purchases')?['body/value'])}` **is greater than** `0`

Add everything below inside **If yes**. Leave *If no* empty.

**A3. Data operation *Filter array* – *Overdue Purchases***

* From: `@{outputs('Get_Pending_Purchases')?['body/value']}`
* Click **Edit in advanced mode** and paste:

```
@greaterOrEquals(div(sub(ticks(utcNow()), ticks(coalesce(item()?['DecisionDate'], item()?['Created']))), 864000000000), variables('EscalateAfterDays'))
```

(`864000000000` is the number of ticks in one day, so this computes whole
days since the CEO approved.)

**A4. Data operation *Select* – *Purchase Rows***

* From: `@{outputs('Get_Pending_Purchases')?['body/value']}`
* Switch **Map** to **text mode** (the `T` icon next to the key/value
  fields), then paste the expression below into the single box (as an
  *Expression*, without the `@{}`):

```
concat(
  '<tr style="background:', if(greaterOrEquals(div(sub(ticks(utcNow()), ticks(coalesce(item()?['DecisionDate'], item()?['Created']))), 864000000000), variables('EscalateAfterDays')), '#fde7e9', '#ffffff'), '">',
  '<td><a href="', item()?['{Link}'], '">#', string(item()?['ID']), ' – ', item()?['Title'], '</a></td>',
  '<td>', coalesce(item()?['Author']?['DisplayName'], ''), '</td>',
  '<td>', coalesce(item()?['Department']?['Value'], ''), '</td>',
  '<td style="text-align:right">', formatNumber(float(coalesce(item()?['EstimatedCost'], 0)), 'N2'), '</td>',
  '<td>', coalesce(item()?['Urgency']?['Value'], ''), '</td>',
  '<td>', if(empty(item()?['NeededBy']), '–', formatDateTime(item()?['NeededBy'], 'dd MMM yyyy')), '</td>',
  '<td>', formatDateTime(coalesce(item()?['DecisionDate'], item()?['Created']), 'dd MMM yyyy'), '</td>',
  '<td style="text-align:right"><b>', string(div(sub(ticks(utcNow()), ticks(coalesce(item()?['DecisionDate'], item()?['Created']))), 864000000000)), '</b></td>',
  '<td style="text-align:right">', string(coalesce(item()?['ReminderCount'], 0)), '</td>',
  '</tr>'
)
```

> The expression editor accepts line breaks. If yours doesn't, remove them.

**A5. Send an email (V2) – *Finance Digest***

| Field | Value |
|---|---|
| To | `FinanceEmail` variable |
| CC | `@{if(greater(length(body('Overdue_Purchases')), 0), variables('CEOEmail'), '')}` |
| Subject | `Reminder: @{length(outputs('Get_Pending_Purchases')?['body/value'])} approved purchase(s) awaiting action@{if(greater(length(body('Overdue_Purchases')), 0), concat(' – ', string(length(body('Overdue_Purchases'))), ' overdue'), '')}` |
| Importance | `@{if(greater(length(body('Overdue_Purchases')), 0), 'High', 'Normal')}` (choose *Enter custom value*) |
| Body | *(code view)* |

```html
<p>Hello Finance team,</p>
<p>These purchase requests have been <b>approved by the CEO</b> and are waiting to be purchased.
Rows highlighted in red have waited <b>@{variables('EscalateAfterDays')} days or more</b>.</p>
<p>When a purchase is done, open the request → <b>Edit</b> → set <b>Status = Purchased</b> and fill in the
PO / invoice number and actual cost. It will then drop off this list.</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc;font-family:Segoe UI,Arial,sans-serif;font-size:13px">
  <tr style="background:#f3f2f1;text-align:left">
    <th>Request</th><th>Requester</th><th>Dept</th><th>Est. cost</th><th>Urgency</th>
    <th>Needed by</th><th>Approved</th><th>Days waiting</th><th>Reminders</th>
  </tr>
  @{join(body('Purchase_Rows'), '')}
</table>
<p>Total pending: <b>@{length(outputs('Get_Pending_Purchases')?['body/value'])}</b> &nbsp;|&nbsp; Overdue: <b>@{length(body('Overdue_Purchases'))}</b></p>
```

**A6. Apply to each – *Record Reminder*** (after A5)

* Select an output: `@{outputs('Get_Pending_Purchases')?['body/value']}`
* Settings → Concurrency control **On**, degree `10` (faster).
* Inside: **Update item**
  * Id: `@{items('Record_Reminder')?['ID']}`
  * Title: `@{items('Record_Reminder')?['Title']}`
  * Status Value: `Approved - Pending Purchase` (keeps the choice as is)
  * Reminders Sent: `@{add(coalesce(items('Record_Reminder')?['ReminderCount'], 0), 1)}`
  * Last Reminder: `@{utcNow()}`

  These updates don't trigger PR-02, because its trigger condition requires
  *Status = Purchased*.

---

### Branch B – CEO nudge for stale approvals

Add a **parallel branch** after the last *Initialize variable*.

**B1. Get items – *Get Stale Approvals***

| Field | Value |
|---|---|
| Filter Query | `RequestStatus eq 'Pending CEO Approval' and Created lt '@{addDays(utcNow(), mul(-1, variables('CEOReminderAfterDays')))}'` |
| Order By | `Created asc` |
| Top Count | `500` |

**B2. Condition – *Any Stale?***: `@{length(outputs('Get_Stale_Approvals')?['body/value'])}` is greater than `0`.

**B3. Select – *Approval Rows*** (text mode, inside *If yes*):

```
concat(
  '<tr>',
  '<td><a href="', item()?['{Link}'], '">#', string(item()?['ID']), ' – ', item()?['Title'], '</a></td>',
  '<td>', coalesce(item()?['Author']?['DisplayName'], ''), '</td>',
  '<td style="text-align:right">', formatNumber(float(coalesce(item()?['EstimatedCost'], 0)), 'N2'), '</td>',
  '<td>', coalesce(item()?['Urgency']?['Value'], ''), '</td>',
  '<td style="text-align:right"><b>', string(div(sub(ticks(utcNow()), ticks(item()?['Created'])), 864000000000)), '</b></td>',
  '</tr>'
)
```

**B4. Send an email (V2) – *CEO Nudge***

| Field | Value |
|---|---|
| To | `CEOEmail` variable |
| Subject | `@{length(outputs('Get_Stale_Approvals')?['body/value'])} purchase request(s) awaiting your approval` |
| Body | see below |

```html
<p>These purchase requests have been waiting for your approval for more than @{variables('CEOReminderAfterDays')} days.</p>
<p>Approve or reject them from the original approval email, or from the <b>Approvals</b> app in Microsoft Teams.</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc;font-family:Segoe UI,Arial,sans-serif;font-size:13px">
  <tr style="background:#f3f2f1;text-align:left"><th>Request</th><th>Requester</th><th>Est. cost</th><th>Urgency</th><th>Days waiting</th></tr>
  @{join(body('Approval_Rows'), '')}
</table>
```

## Notes

* **The Finance digest is intentionally a single email**, not one email per
  request. If you'd rather send one email per overdue request, move the
  email inside the *Apply to each* loop and filter it with a condition.
* **Titles with `<` or `&`:** these are inserted into HTML as is. That's fine
  for normal text. If staff paste HTML into titles, wrap the value in
  `replace(replace(item()?['Title'], '&', '&amp;'), '<', '&lt;')`.
* **More than 500 open requests:** turn on *Pagination* in the *Get items*
  settings and set the threshold to 5000.
