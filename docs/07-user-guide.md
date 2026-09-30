# 05 – User guide

Share this page (or copy it into your intranet) when you roll out the process.

## Employees: submitting a purchase request

1. Open the **Purchase Requests** list (link: `https://yourorg.sharepoint.com/sites/Operations/Lists/PurchaseRequests`)
   or the *Purchase Requests* tab in Teams.
2. Click **+ New** and fill in:
   * **Item / Service Requested**: a short name, e.g. *"Dell 27" monitor"*
   * **Description**, **Quantity**, **Estimated Total Cost**
   * **Business Justification**: why it's needed
   * **Project**: the project this is for (use **GEN - General / Overhead**
     if it isn't for a specific project)
   * **Department**, **Urgency**, **Needed By**, **Suggested Vendor / Link**
   * Attach any quotes or screenshots with **Add attachments**
3. Click **Save**. You'll get emails when the CEO decides, when Finance
   places the order, if the delivery is delayed, and when it arrives at the
   office.
4. To check progress at any time, open the list. The **My Requests** view
   shows the *Status* of each of your requests.

**If Finance finds a duplicate** (e.g. a colleague asked for the same
thing), you may get an approval request asking to **merge** your request
into another one. If you approve, your request is closed as *Merged* and you
get all further updates (ordered, delayed, received) for the combined one.
If you reject, nothing changes.

You can't edit a request after submitting it. If something needs to
change, ask Finance to set it to **Cancelled**, then submit a new one.

## CEO: approving requests

* Each new request arrives as an **approval email** in Outlook with
  **Approve / Reject** buttons and a comments box. It also appears in the
  **Approvals** app in Teams and the Power Automate mobile app.
* The approval shows the **project**, and, if the budget check is set
  up, the project's budget, what's already committed and what would remain,
  with a ⚠️ if it would go over budget or the project is closed.
* Your comments are saved on the request and sent to the requester (and to
  Finance, for approvals).
* If you haven't responded after 2 days, you'll get a reminder listing all
  approvals still waiting. Requests expire after 28 days without a response.
* You're copied on the Finance reminder whenever an approved purchase has
  been waiting 5 days or more.

## Finance: placing the order

**Assign a supplier.** Set **Supplier** on each approved request (pick from
the *Suppliers* list; add new suppliers there). In the **Pending Purchase
by Supplier** view you can select several unassigned requests → **Edit** →
set Supplier for all of them at once.

**Merge duplicates** before ordering: on the request to close, set **Merge
Into Request #** to the number of the request to keep, choose a **Merge
Mode**, and save. The requester(s) are asked to approve. *Merge State* shows
progress. Details: [10 – Merge duplicates](10-flow-merge-duplicates.md).

**Order several items from one supplier at once:** in *Pending Purchase by
Supplier*, select any request in the supplier's group → **Automate → Order
all from this supplier** → enter the PO number and expected date. This
emails you the consolidated order (and optionally the supplier) and can
mark every item *Purchased* in one go. Details:
[11 – Supplier batch order](11-flow-supplier-batch-order.md).

**Or order one request at a time:**

1. Approved requests arrive by email (subject *"Action needed: approved
   purchase #…"*) and appear in the **Pending Purchase** view, oldest first.
2. Make the purchase.
3. Open the request → **Edit** (or **Edit in grid view** from the
   *Pending Purchase* view to update several at once) and set:
   * **Status** → **Purchased**
   * **PO / Invoice Number**, **Actual Cost**, optional **Finance Notes**
   * **Expected Delivery Date** (important: delivery tracking uses it)
   * **Carrier / Courier** and **Tracking Number / Link**, if you have them
   * **Purchased On** (leave it blank to use today's date)
   * Attach the PO or invoice
4. **Save.** The requester and the inventory manager are emailed
   automatically, and the request drops off your reminder list.

Until then, a **reminder digest arrives every weekday at 9:00** listing all
open purchases and how long each has been waiting. Requests waiting 5 days
or more are highlighted, and the CEO is copied.

To withdraw a request, set **Status → Cancelled**. This stops the reminders.

Finance is also copied when an order arrives (to match the invoice), when
it's delayed, and when an order is 3 or more days late (to chase the vendor).

## Inventory manager: tracking deliveries and marking them received

Each time Finance places an order, you get an **"Incoming order"** email.
Every weekday at 8:45 you also get a **Delivery tracker** email listing all
open orders, most late first: 🔴 past due, 🟡 due in the next 2 days or
missing an expected date.

In the list, use the **Awaiting Delivery** view (all open orders, by due
date) and **Overdue Deliveries** (past due only). Open a request →
**Edit** and update it as the order progresses:

| When | Set |
|---|---|
| Vendor confirms dispatch | **Status = In Transit**; **Carrier / Courier**; **Tracking Number / Link**; **Revised Delivery Date** if the ETA changed |
| It's running late | **Status = Delayed**; **Revised Delivery Date**; **Delay Reason**. The requester and Finance are emailed. Each later change to the revised date sends one new update. |
| Part of it arrives | **Status = Partially Received**; **Quantity Received** so far |
| Everything arrives | **Status = Received**; **Quantity Received**; **Receipt Notes / Condition** (any damage); attach a photo of the delivery note. *Received On* and *Received By* fill in automatically if left blank. The requester is told to collect it. |

At each step, add a line to **Delivery Updates** (e.g. *"Called vendor,
shipped from warehouse today"*). Every entry is kept with the date and your
name, giving a full tracking history.

Orders that pass their due date while still *Purchased* or *In Transit* are
set to **Delayed** automatically, and the requester is told. When you get a
new date from the vendor, set the **Revised Delivery Date**.
