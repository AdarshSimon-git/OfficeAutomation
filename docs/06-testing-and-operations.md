# 06 – Testing & operations

## Ownership

* **Build the flows under a service account** (e.g.
  `automation@yourorg.com`, licensed for Microsoft 365). Emails are sent
  from that account's mailbox, and the flows keep running when staff leave.
  Add the account to the **Purchase Request Managers** group so it can
  update every item.
* Add at least one person as a **co-owner** of each flow (flow details →
  *Owners → Edit*) so someone else can fix it.
* To send emails from a shared mailbox such as `purchasing@yourorg.com`,
  use *Send an email from a shared mailbox (V2)* instead of *Send an email
  (V2)*. The service account needs *Send As* permission on it.

## Licensing

Everything uses **standard** connectors (SharePoint, Approvals, Office 365
Outlook, Microsoft Teams), which are included with Microsoft 365 Business
Basic/Standard/Premium and E3/E5. No Power Automate Premium is required.

## Test plan

Put your own addresses in `CEOEmail` and `FinanceEmail` while testing, then
switch to the real ones.

| # | Test | Expected |
|---|---|---|
| 1 | As a *member*, submit a request | Status becomes **Pending CEO Approval** within about a minute; the CEO gets an approval in Outlook and Teams |
| 2 | As the member, try to edit the item | No **Edit** option (read-only) |
| 3 | As a second member, open the list | They can't see the first member's request |
| 4 | CEO **Rejects** with a comment | Status **Rejected**; CEO Comments and Decision Date filled; requester gets the rejection email with the comment |
| 5 | Submit again; CEO **Approves** | Status **Approved - Pending Purchase**; Finance and requester emailed |
| 6 | Run PR-03 manually (**Run** button) | Finance digest lists the request; *Reminders Sent* = 1 |
| 7 | Temporarily set `EscalateAfterDays` to `0` and run PR-03 | Row highlighted, CEO copied, High importance. Reset to 5 afterwards. |
| 8 | Temporarily set `CEOReminderAfterDays` to `0`, leave a request pending approval, run PR-03 | CEO gets the nudge |
| 9 | As Finance, set Status **Purchased**, add a PO number | Requester gets the purchased email; *Purchased On* filled; *Completion Notified* = Yes; PR-02 ran **once** |
| 10 | Run PR-03 again | The purchased request is no longer listed; if nothing else is pending, no email |
| 11 | Set a request **Cancelled** | It stops appearing in reminders |

## Monitoring

* Each flow's **Run history** (28 days) shows every run. Failures appear in
  red.
* Power Automate emails the owners a weekly summary of failures by default.
  For faster alerts, add a *Scope* around the main actions plus a parallel
  "notify admin" email set to run after *has failed*.
* Quick health checks in the list:
  * **Pending Purchase** view sorted by *Reminders Sent*: purchases Finance
    keeps missing.
  * **Awaiting CEO Approval**: anything older than a few days.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Nothing happens after submitting | PR-01 is off or its connection has expired: open the flow → *Turn on* / fix connections. Also check the list URL in the trigger. |
| Status stays **Submitted** | PR-01 failed at *Mark Pending Approval*. The flow account probably lacks Edit on the list: add it to *Purchase Request Managers*. |
| Get items returns nothing | Filter text must match the Status choice exactly: `Approved - Pending Purchase` (spaces around the hyphen). The column's internal name must be `RequestStatus`: check under List settings → click the column → `Field=` in the URL. |
| PR-02 runs twice or loops | The trigger condition is missing or has a typo. Check *Completion Notified* exists and PR-02 sets it to Yes. |
| A request was set back from Purchased and purchased again, but no email | *Completion Notified* is still Yes: set it to No in grid view (or unhide it) before marking Purchased again. |
| Approval expired | The CEO didn't respond within 28 days. Resubmit. Consider adding a delegate: use *Approve/Reject – First to respond* with the CEO and an EA/COO separated by `;`. |
| Emails come from a person, not a service account | The flow was built under that person's connection. Change the Outlook connection to the service account. |

## Possible extensions

* **Approval tiers:** add a condition in PR-01 so requests under a threshold
  (e.g. `EstimatedCost` < 500) go to the department head instead of the CEO,
  or skip approval entirely.
* **Budget tracking:** a Power BI report on the list (spend by department /
  month using *Actual Cost* and *Purchased On*).
* **Microsoft Forms intake:** for external or kiosk users, a Form plus a
  flow that creates the list item. PR-01 then triggers as usual.
* **Adaptive card for Finance in Teams:** replace step 6c of PR-01 with
  *Post adaptive card and wait for a response* ("Mark as purchased" with PO
  number fields) to close requests without opening SharePoint. Note that
  this keeps that PR-01 run waiting until Finance responds.
