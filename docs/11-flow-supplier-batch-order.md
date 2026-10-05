# 11 – Grouping by supplier & Flow PR-07: Order All From Supplier

This lets Finance order **every approved item from one supplier in a single
order**, instead of placing one order per request.

## How it works for Finance

1. **Assign suppliers.** Open the **Pending Purchase by Supplier** view.
   Requests with no supplier yet are in the **Supplier: (empty)** group at
   the top. Select several (tick boxes) → **Edit** (details pane) → set
   **Supplier** for all of them at once. Requesters' ideas are in
   *Suggested Vendor / Link*. Add new suppliers in the **Suppliers** list.
2. **Review a supplier group.** Each group header shows the **number of
   items** and the **total estimated cost**. Expand it to see every
   request, with quantity, requester, project and urgency. Merge any
   duplicates first ([10](10-flow-merge-duplicates.md)).
3. **Order the group.** Select **any one request** in the group →
   **Automate** (toolbar, or `…` on the item) → **Order all from this
   supplier**. Fill in:
   * **PO Number** (applied to all items in the batch)
   * **Expected Delivery Date** (optional)
   * **Mark all as Purchased?** Yes / No
   * **Email the order to the supplier?** Yes / No
4. The flow collects **every** *Approved - Pending Purchase* request with
   that supplier and:
   * emails **you and Finance** a consolidated order sheet (items,
     quantities, requesters, projects, estimated total);
   * optionally emails the **supplier** an order with just the items and
     quantities (no internal details) at the address in the *Suppliers*
     list, copying you and Finance;
   * optionally marks **all of them *Purchased*** with the PO number,
     expected date and today's date. PR-02 then notifies each requester and
     the inventory manager as usual, and they all appear in the inventory
     delivery tracker.
5. When the invoice arrives, fill in each request's **Actual Cost** (grid
   view makes this quick). Filter the *Received* or *By Project* views by
   *PO / Invoice Number* to see everything on one invoice.

Grouping in other views: any view can be grouped by *Supplier* (column
header → **Group by Supplier**), e.g. *Awaiting Delivery* to see what's
outstanding from each supplier.

## The Suppliers list

| Column | Use |
|---|---|
| Supplier (Title) | Name shown in the dropdown |
| Contact Name, Phone, Website / Portal | Reference |
| **Orders Email** | Where PR-07 sends the order when you choose to email it |
| Payment Terms, Notes | Reference |
| Active | Untick for suppliers you no longer use (they still appear in the dropdown, a SharePoint lookup limitation, so you can also prefix the name with `[OLD]`) |

## Build the flow

**Create → Instant cloud flow → skip**, then choose the SharePoint trigger
**For a selected item**. Name it **`Order all from this supplier`**: that
exact name is what Finance sees in the list's *Automate* menu.

### 1. Trigger – *For a selected item*

Site Address = your site, List Name = *Purchase Requests*. Add inputs:

| Input type | Name | Required |
|---|---|---|
| Text | `PO Number` | Yes |
| Date | `Expected Delivery Date` | No |
| Yes/No | `Mark all as Purchased?` | Yes |
| Yes/No | `Email the order to the supplier?` | Yes |

In the steps below, pick these inputs from **dynamic content** (under the
trigger). Their expression names are usually `triggerBody()?['text']`,
`['date']`, `['boolean']` and `['boolean_1']`. Hover the token to check.

### 2. Variables

| Name | Type | Value |
|---|---|---|
| `FinanceEmail` | String | `finance@yourorg.com` |
| `OrgName` | String | `Your Organisation Ltd` |
| `RunBy` | String | `@{triggerOutputs()?['headers']?['x-ms-user-email']}` (who clicked) |

### 3. Get item – "Selected Request"

List *Purchase Requests*, Id = trigger **ID** (`@{triggerBody()?['entity']?['ID']}`).

### 4. Condition – "Has Supplier?"

`@empty(outputs('Selected_Request')?['body/Supplier/Id'])` is equal to `true`
→ **If yes**: email `RunBy` *"Request #… has no Supplier. Set a Supplier
first, then run again."*, then **Terminate** (Succeeded).

### 5. Get item – "Supplier Details"

List *Suppliers*, Id `@{outputs('Selected_Request')?['body/Supplier/Id']}`.

### 6. Get items – "Supplier Batch"

| Field | Value |
|---|---|
| List | *Purchase Requests* |
| Filter Query | `RequestStatus eq 'Approved - Pending Purchase' and SupplierId eq @{outputs('Selected_Request')?['body/Supplier/Id']}` |
| Order By | `Title asc` |
| Top Count | `500` |

(If your tenant rejects `SupplierId`, use `Supplier/Id`.)

Add a **Condition "Anything to order?"**: if `length(outputs('Supplier_Batch')?['body/value'])`
is `0`, email `RunBy` that there are no approved requests for this supplier
and **Terminate**. This happens if the selected item was already ordered.

### 7. Select – "Internal Lines" (text mode)

From `@{outputs('Supplier_Batch')?['body/value']}`:

```
concat('<tr>',
  '<td><a href="', item()?['{Link}'], '">#', string(item()?['ID']), '</a></td>',
  '<td><b>', item()?['Title'], '</b><br/><small>', coalesce(item()?['ItemDescription'], ''), '</small></td>',
  '<td style="text-align:right">', string(item()?['Quantity']), '</td>',
  '<td>', coalesce(item()?['Author']?['DisplayName'], ''), '</td>',
  '<td>', coalesce(item()?['Project']?['Value'], '–'), '</td>',
  '<td>', coalesce(item()?['Urgency']?['Value'], ''), '</td>',
  '<td style="text-align:right">', formatNumber(float(coalesce(item()?['EstimatedCost'], 0)), 'N2'), '</td>',
  '</tr>')
```

### 8. Select – "Supplier Lines" (text mode)

Same *From*. This is only what the supplier needs to see:

```
concat('<tr>',
  '<td>', string(item()?['ID']), '</td>',
  '<td><b>', item()?['Title'], '</b><br/><small>', coalesce(item()?['ItemDescription'], ''), '</small></td>',
  '<td style="text-align:right">', string(item()?['Quantity']), '</td>',
  '<td><small>', coalesce(item()?['Vendor'], ''), '</small></td>',
  '</tr>')
```

### 9. Select – "Batch Costs" (text mode) and Compose – "Batch Total"

Select map: `float(coalesce(item()?['EstimatedCost'], 0))`

Compose:
```
xpath(xml(json(concat('{"r":{"v":', string(body('Batch_Costs')), '}}'))), 'sum(/r/v)')
```

### 10. Condition – "Email Supplier?"

`Email the order to the supplier?` (dynamic content) is equal to `true`
**and** `@{outputs('Supplier_Details')?['body/SupplierEmail']}` is not equal to (blank).

**If yes → Send an email (V2) – "Supplier Order"**

| Field | Value |
|---|---|
| To | `@{outputs('Supplier_Details')?['body/SupplierEmail']}` |
| CC | `@{variables('RunBy')};@{variables('FinanceEmail')}` |
| Subject | `Purchase order @{PO Number} – @{variables('OrgName')}` |
| Body | *(code view)* |

```html
<p>Dear @{coalesce(outputs('Supplier_Details')?['body/ContactName'], outputs('Supplier_Details')?['body/Title'])},</p>
<p>Please supply the following items under purchase order <b>@{PO Number}</b>.</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc;font-family:Segoe UI,Arial,sans-serif;font-size:13px">
  <tr style="background:#f3f2f1;text-align:left"><th>Line ref</th><th>Item</th><th>Qty</th><th>Reference / link</th></tr>
  @{join(body('Supplier_Lines'), '')}
</table>
<p>Requested delivery date: <b>@{if(empty(Expected Delivery Date), 'as soon as possible', formatDateTime(coalesce(Expected Delivery Date, utcNow()), 'dd MMM yyyy'))}</b></p>
<p>Please confirm prices, availability and delivery date by replying to this email, and quote the PO number on your invoice.</p>
<p>Kind regards,<br/>@{variables('OrgName')} – Finance</p>
```

(Replace `@{PO Number}` and `Expected Delivery Date` with the dynamic
content tokens.)

If you'd rather check the email before it goes out, use **Draft an email
message** (Office 365 Outlook) instead of *Send*. The draft lands in the
flow account's Drafts folder, so this works best with a shared mailbox.

### 11. Send an email (V2) – "Batch Summary" (always)

| Field | Value |
|---|---|
| To | `@{variables('RunBy')}` |
| CC | `FinanceEmail` |
| Subject | `Batch order @{PO Number}: @{length(outputs('Supplier_Batch')?['body/value'])} item(s) from @{outputs('Supplier_Details')?['body/Title']}` |
| Body | *(code view)* |

```html
<p>Batch order <b>@{PO Number}</b> for <b>@{outputs('Supplier_Details')?['body/Title']}</b>
(@{outputs('Supplier_Details')?['body/PaymentTerms']}).</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc;font-family:Segoe UI,Arial,sans-serif;font-size:13px">
  <tr style="background:#f3f2f1;text-align:left"><th>Req</th><th>Item</th><th>Qty</th><th>Requester</th><th>Project</th><th>Urgency</th><th>Est. cost</th></tr>
  @{join(body('Internal_Lines'), '')}
  <tr><td colspan="6" style="text-align:right"><b>Estimated total</b></td><td style="text-align:right"><b>@{formatNumber(float(outputs('Batch_Total')), 'N2')}</b></td></tr>
</table>
<p>Supplier emailed: <b>@{if(and(equals(Email the order to the supplier?, true), not(empty(outputs('Supplier_Details')?['body/SupplierEmail']))), outputs('Supplier_Details')?['body/SupplierEmail'], 'No')}</b>
&nbsp;|&nbsp; Marked as Purchased: <b>@{if(equals(Mark all as Purchased?, true), 'Yes', 'No – set Status = Purchased on each request once the order is confirmed')}</b></p>
```

### 12. Condition – "Mark Purchased?"

`Mark all as Purchased?` is equal to `true`. **If yes → Apply to each**
over `@{outputs('Supplier_Batch')?['body/value']}`, renamed **Order Each**
(Concurrency on, degree 5), containing **Update item**:

| Field | Value |
|---|---|
| Id | `@{items('Order_Each')?['ID']}` |
| Title | `@{items('Order_Each')?['Title']}` |
| Status Value | `Purchased` |
| PO / Invoice Number | `PO Number` (dynamic content) |
| Expected Delivery Date | `Expected Delivery Date` (dynamic content) |
| Purchased On | `@{utcNow()}` |
| Finance Notes | `@{concat(coalesce(items('Order_Each')?['FinanceNotes'], ''), decodeUriComponent('%0A'), 'Batch-ordered with ', string(length(outputs('Supplier_Batch')?['body/value'])), ' item(s) from ', outputs('Supplier_Details')?['body/Title'], ' on PO ', PO Number, ' by ', variables('RunBy'), '.')}` |

Each update fires **PR-02**, so every requester (and anyone merged into
their request) gets an *Ordered* email, and the inventory manager gets an
*Incoming order* email per item.

> **One email per batch for Inventory instead of one per item:** CC
> `InventoryEmail` on the *Batch Summary* (step 11). Then in PR-02, wrap
> *Email Inventory Incoming* in a condition that skips it when
> `@{contains(coalesce(triggerOutputs()?['body/FinanceNotes'], ''), 'Batch-ordered')}`
> is `true`. Requesters still get their individual emails.

### 13. Share it with Finance

For the flow to show up in the list's **Automate** menu for Finance:

1. Flow details page → **Run only users → Edit**.
2. Add the Finance users, or a Microsoft 365 / security group containing
   them. SharePoint groups can't be used here.
3. For each connection, choose **Use this connection (automation@…)**, so
   the flow acts as the service account and Finance needn't have their own
   connections.

Requesters don't see it: they aren't run-only users, and they don't have
edit rights anyway.
