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

Put your own addresses in `CEOEmail`, `FinanceEmail` and `InventoryEmail` while testing, then
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
| 9 | As Finance, set Status **Purchased**, add a PO number and an Expected Delivery Date of tomorrow | Requester gets *Ordered*; Inventory gets *Incoming order*; *Purchased On* filled; *Completion Notified* = Yes; PR-02 ran **once** |
| 10 | Run PR-03 again | The purchased request is no longer listed; if nothing else is pending, no email |
| 11 | Run PR-05 manually | Inventory digest lists the order in amber ("in 1 days"); no Finance CC |
| 12 | As Inventory, set **In Transit** with carrier and tracking, add a *Delivery Updates* note | No emails; the note appears in the item's history |
| 13 | Set the Expected Delivery Date to 4 days ago, then run PR-05 | Row red "4 days late"; Finance copied; High importance; status auto-set to **Delayed**; requester + Finance get one delay email (PR-04) |
| 14 | Enter a Revised Delivery Date and save, then save again without changing it | **One** new delay email after the first save, none after the second |
| 15 | Set **Received** with Quantity Received less than Quantity | Requester gets *Arrived* with "(short delivery)"; Finance copied; *Received On/By* filled; *Received Notified* = Yes; PR-04 ran once |
| 16 | Run PR-05 again | The received order is no longer listed |
| 17 | Set a request **Cancelled** | It stops appearing in all reminders |
| **Teams channel** | | |
| 18a | Submit a request | A new thread appears in *Purchase Requests* with the details, and the CEO is @mentioned; *Teams Thread ID* is filled in on the item (visible in grid view if unhidden) |
| 18b | Approve it, mark it Purchased, set Delayed, then Received | ✅, 🛒, ⏰ and 📦 replies appear **in the same thread**, in order |
| 18c | Temporarily pick a channel the flow account can't post to, and submit | The approval still reaches the CEO; the thread ID is blank; no replies are attempted |
| **Projects** | | |
| 18 | Create project *PRJ-T Test* with Budget 1,000. Submit a request for it costing 800, get it approved, then submit another for 300 | The second approval shows committed 800, remaining −100 and ⚠️ Over budget (with the budget check) |
| 19 | Set the project to *Closed* and submit another request for it | Approval shows ⚠️ Project is Closed |
| 20 | Open the **By Project** view | Requests grouped under *PRJ-T Test* with Sum totals |
| **Merge duplicates** | | |
| 21 | Two members (A and B) each submit "Test laptop bag", qty 1 and 2; both approved | Two requests in *Pending Purchase* |
| 22 | As Finance, on B's request set **Merge Into** = A's ID and save | B's *Merge State* = Awaiting Requester Approval; **both A and B** get a merge approval |
| 23 | A and B both approve | A's request: qty 3, estimate summed, *Merged Requests* lists B's; B's request: Status **Merged**; confirmation email to A, B and Finance |
| 24 | Mark A's request Purchased, then Received | **B is copied** on the Ordered and Arrived emails |
| 25 | Try merging into a non-existent ID, or into a request still Pending CEO Approval | *Merge State* = Invalid; *Merge Into* cleared; Finance emailed the reason; no approval sent |
| 26 | Propose a merge and have one requester reject | *Merge State* = Declined; both requests unchanged |
| **Supplier batching** | | |
| 27 | Create supplier *Test Supplier* (Orders Email = your address). Assign it to 3 approved requests using bulk edit | The 3 appear under *Test Supplier* in **Pending Purchase by Supplier**, with count 3 and summed cost |
| 28 | Select one → **Automate → Order all from this supplier**: PO `TEST-001`, mark purchased = Yes, email supplier = Yes | Supplier email (items and quantities only); batch summary to you; all 3 now **Purchased** with PO TEST-001; PR-02 ran 3 times (3 requester emails) |
| 29 | Run it on a request with no Supplier | Email "set a Supplier first"; nothing changed |

## Monitoring

* Each flow's **Run history** (28 days) shows every run. Failures appear in
  red.
* Power Automate emails the owners a weekly summary of failures by default.
  For faster alerts, add a *Scope* around the main actions plus a parallel
  "notify admin" email set to run after *has failed*.
* Quick health checks in the list:
  * **Overdue Deliveries**: orders past due, and whether each has a revised
    date and reason.
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
| PR-04 sends a delay email on every save | Its trigger condition is missing, or *Stamp Delay Notice* isn't writing *Last Delay Notice*. |
| An order shows as late on its due day | `TimeZone` in PR-05 is wrong: use the Windows ID, e.g. `India Standard Time`. |
| Overdue Deliveries view is empty but the digest shows late orders | The view compares *Delivery Due* with today's date. Check the order has an Expected or Revised date. |
| PR-06 or PR-07 *Get items* fails on `ProjectId` / `SupplierId` | Use `Project/Id eq …` / `Supplier/Id eq …` instead. The column's internal name must be exactly `Project` / `Supplier`. |
| "Order all from this supplier" isn't in the Automate menu | The user isn't a run-only user of PR-07, or the browser cached the menu: refresh. The flow must use the *For a selected item* trigger on this list. |
| Merge approval never arrives | PR-06's trigger condition is too strict: check *Merge State* is blank on the request (no default value on that column). |
| Thread replies appear as new posts, or fail with "message not found" | The *Message ID* must be the root post's ID (`TeamsThreadId`), and the reply must use the **same Team and Channel** as the original post. |
| Posts show as "Workflows" instead of "Flow bot" | Expected: Microsoft renamed the bot. |
| CEO isn't notified in Teams | Check the *CEO Mention* token is in the message, and that the CEO is a member of the team. |
| *Received By* isn't filled in | Check the claims expression in PR-04 (`i:0#.f|membership|` + email), and that the flow account can resolve users on the site. |
| A request was set back from Purchased and purchased again, but no email | *Completion Notified* is still Yes: set it to No in grid view (or unhide it) before marking Purchased again. The same applies to *Received Notified* for Received. |
| Approval expired | The CEO didn't respond within 28 days. Resubmit. Consider adding a delegate: use *Approve/Reject – First to respond* with the CEO and an EA/COO separated by `;`. |
| Emails come from a person, not a service account | The flow was built under that person's connection. Change the Outlook connection to the service account. |

## Possible extensions

* **Approval tiers:** add a condition in PR-01 so requests under a threshold
  (e.g. `EstimatedCost` < 500) go to the department head instead of the CEO,
  or skip approval entirely.
* **Budget and vendor reporting:** a Power BI report on the list: spend by
  department / month (*Actual Cost*, *Purchased On*), and vendor
  performance, i.e. average days late (*Received On* minus *Expected
  Delivery Date*) by *Vendor*.
* **Microsoft Forms intake:** for external or kiosk users, a Form plus a
  flow that creates the list item. PR-01 then triggers as usual.
* **Adaptive card for Finance in Teams:** replace step 6c of PR-01 with
  *Post adaptive card and wait for a response* ("Mark as purchased" with PO
  number fields) to close requests without opening SharePoint. Note that
  this keeps that PR-01 run waiting until Finance responds.
