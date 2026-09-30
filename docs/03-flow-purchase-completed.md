# 03 – Flow PR-02: Purchase Completed

**Trigger:** Finance sets a request's **Status** to **Purchased**
**Result:** *Purchased On* is filled in (if Finance left it blank), the
request is flagged as notified, and the requester gets an email. The request
also drops out of the reminder digest because its status changed.

```
When an item is created or modified   (trigger condition: Status = Purchased AND not yet notified)
├─ Update item     Stamp Completion
└─ Send an email   Email Requester Purchased
```

## Build it

**Create → Automated cloud flow**, name it `PR-02 Purchase Completed`, and
pick the SharePoint trigger **When an item is created or modified**.

### 1. Trigger – *When an item is created or modified*

Site Address and List Name: same as PR-01.

**Trigger condition** (important: it keeps the flow from running on every
edit and from looping on its own update). Open the trigger → `…` →
**Settings** → **Trigger conditions → + Add**, and paste:

```
@and(equals(triggerOutputs()?['body/RequestStatus/Value'], 'Purchased'), not(equals(triggerOutputs()?['body/CompletionNotified'], true)))
```

### 2. Update item – rename to **Stamp Completion**

| Field | Value |
|---|---|
| Id | trigger `ID` |
| Title | trigger `Title` |
| Status Value | `Purchased` (the connector may otherwise reset the choice) |
| Purchased On | `@{if(empty(triggerOutputs()?['body/PurchasedOn']), utcNow(), triggerOutputs()?['body/PurchasedOn'])}` |
| Completion Notified | `Yes` |

This update triggers the flow again, but the trigger condition is now false
(*Completion Notified = Yes*), so it doesn't run a second time.

### 3. Send an email (V2) – rename to **Email Requester Purchased**

| Field | Value |
|---|---|
| To | `@{triggerOutputs()?['body/Author/Email']}` |
| CC | *(optional)* the CEO variable or the Finance DL |
| Subject | `Purchased: your request #@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}` |
| Body | *(code view)* |

```html
<p>Hi @{triggerOutputs()?['body/Author/DisplayName']},</p>
<p>Finance has completed the purchase for your request <b>#@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}</b>.</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc">
  <tr><td><b>PO / invoice number</b></td><td>@{triggerOutputs()?['body/PONumber']}</td></tr>
  <tr><td><b>Actual cost</b></td><td>@{triggerOutputs()?['body/ActualCost']}</td></tr>
  <tr><td><b>Finance notes</b></td><td>@{triggerOutputs()?['body/FinanceNotes']}</td></tr>
  <tr><td><b>Completed by</b></td><td>@{triggerOutputs()?['body/Editor/DisplayName']}</td></tr>
</table>
<p><a href="@{triggerOutputs()?['body/{Link}']}">View request</a></p>
```

## Optional additions

* **Require a PO number:** add a condition before step 2. If `PONumber` is
  empty, email the editor (`body/Editor/Email`) asking them to add it, and
  end the flow (*Terminate*, status Succeeded). When they add it and save,
  the flow triggers again.
* **Cancelled requests:** create a copy of this flow with the trigger
  condition set to `'Cancelled'`, and email the requester that the request
  was withdrawn.
