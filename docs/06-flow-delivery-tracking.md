# 06 – Flow PR-05: Delivery Tracking Digest

**Trigger:** every weekday at 08:45 (your time zone)
**Result:** the **inventory manager** gets one email listing every order
placed but not yet fully received (*Purchased, In Transit, Delayed,
Partially Received*), sorted most-late first:

| Highlight | Meaning |
|---|---|
| 🔴 red | Past its delivery due date (revised date if set, otherwise expected date), with days late |
| 🟡 amber | Due within `DueSoonDays`, or **no expected date set** (so someone needs to get an ETA) |
| white | On track |

It also:

* **copies Finance** when any order is `ChaseAfterDays` or more late, so
  they can chase the vendor;
* optionally **auto-flags overdue orders as Delayed** (only *Purchased* /
  *In Transit* ones). The status change fires PR-04, which emails the
  requester, and a note is added to the *Delivery Updates* log;
* sends nothing when there are no open orders.

For a live view at any time, the list also has **Awaiting Delivery** and
**Overdue Deliveries** views. Pin *Awaiting Delivery* as a Teams tab for the
inventory team.

```
Recurrence (Mon–Fri 08:45)
├─ Initialize variables: InventoryEmail, FinanceEmail, TimeZone, DueSoonDays, ChaseAfterDays, AutoFlagDelayed
├─ Compose          Today Local
├─ Get items        Get Open Orders
└─ Condition        Any Open Orders?
    └─ Yes: Select Deliveries → Filter arrays (Overdue, Chase List, To Auto Flag)
            → Select Delivery Rows → Send email Delivery Digest
            → [If AutoFlagDelayed] Apply to each To Auto Flag: Update item Status = Delayed
```

## Build it

**Create → Scheduled cloud flow**, name it `PR-05 Delivery Tracking Digest`.

### 1. Recurrence

Frequency `Week`, interval `1`, days Mon–Fri, hour `8`, minute `45`, your
time zone.

### 2. Variables

| Name | Type | Value |
|---|---|---|
| `InventoryEmail` | String | `stores@yourorg.com` |
| `FinanceEmail` | String | `finance@yourorg.com` |
| `TimeZone` | String | Windows time zone ID, e.g. `India Standard Time`, `GMT Standard Time`, `Eastern Standard Time`, `Arabian Standard Time` |
| `DueSoonDays` | Integer | `2` |
| `ChaseAfterDays` | Integer | `3` |
| `AutoFlagDelayed` | Boolean | `true` |

> **Why a time zone?** SharePoint stores date-only values as midnight
> *local* time converted to UTC (e.g. 5 Oct in India is stored as
> `2026-10-04T18:30:00Z`). Comparing in local dates stops items being
> marked late on their due day.

### 3. Compose – rename to **Today Local**

```
formatDateTime(convertFromUtc(utcNow(), variables('TimeZone')), 'yyyy-MM-dd')
```

### 4. Get items – rename to **Get Open Orders**

| Field | Value |
|---|---|
| Filter Query | `RequestStatus eq 'Purchased' or RequestStatus eq 'In Transit' or RequestStatus eq 'Delayed' or RequestStatus eq 'Partially Received'` |
| Top Count | `500` |

### 5. Condition – **Any Open Orders?**

`@{length(outputs('Get_Open_Orders')?['body/value'])}` is greater than `0`.
Put everything below inside **If yes**.

### 6. Select – rename to **Deliveries**

This builds one clean record per order, with the due date and days late
already worked out. From: `@{outputs('Get_Open_Orders')?['body/value']}`.
Map (key/value mode), with each value as an **expression**:

| Key | Value (expression) |
|---|---|
| `ID` | `item()?['ID']` |
| `Title` | `item()?['Title']` |
| `Link` | `item()?['{Link}']` |
| `Status` | `item()?['RequestStatus']?['Value']` |
| `Requester` | `coalesce(item()?['Author']?['DisplayName'], '')` |
| `Vendor` | `coalesce(item()?['Vendor'], '')` |
| `PO` | `coalesce(item()?['PONumber'], '')` |
| `Tracking` | `trim(concat(coalesce(item()?['Carrier'], ''), ' ', coalesce(item()?['TrackingNumber'], '')))` |
| `Ordered` | `formatDateTime(convertFromUtc(coalesce(item()?['PurchasedOn'], item()?['Modified']), variables('TimeZone')), 'dd MMM')` |
| `HasDue` | `not(empty(coalesce(item()?['RevisedDelivery'], item()?['ExpectedDelivery'])))` |
| `Due` | `if(empty(coalesce(item()?['RevisedDelivery'], item()?['ExpectedDelivery'])), 'Not set', formatDateTime(convertFromUtc(coalesce(item()?['RevisedDelivery'], item()?['ExpectedDelivery'], '2999-12-31T00:00:00Z'), variables('TimeZone')), 'dd MMM yyyy'))` |
| `DaysLate` | `if(empty(coalesce(item()?['RevisedDelivery'], item()?['ExpectedDelivery'])), -100000, div(sub(ticks(outputs('Today_Local')), ticks(formatDateTime(convertFromUtc(coalesce(item()?['RevisedDelivery'], item()?['ExpectedDelivery'], '2999-12-31T00:00:00Z'), variables('TimeZone')), 'yyyy-MM-dd'))), 864000000000))` |
| `Revised` | `not(empty(item()?['RevisedDelivery']))` |

`DaysLate` is positive when late, `0` on the due day, and negative before
it. It's `-100000` when there's no date, so those orders sort to the bottom.

### 7. Filter arrays (all *From* `@{body('Deliveries')}`, **Edit in advanced mode**)

| Name | Condition |
|---|---|
| **Overdue** | `@greater(item()?['DaysLate'], 0)` |
| **Chase List** | `@greaterOrEquals(item()?['DaysLate'], variables('ChaseAfterDays'))` |
| **To Auto Flag** | `@and(greater(item()?['DaysLate'], 0), or(equals(item()?['Status'], 'Purchased'), equals(item()?['Status'], 'In Transit')))` |

### 8. Select – rename to **Delivery Rows**

From (expression): `reverse(sort(body('Deliveries'), 'DaysLate'))`, which
puts the most-late first. Switch Map to **text mode** and paste:

```
concat(
  '<tr style="background:',
    if(greater(item()?['DaysLate'], 0), '#fde7e9',
      if(or(not(item()?['HasDue']), greaterOrEquals(item()?['DaysLate'], mul(-1, variables('DueSoonDays')))), '#fff4ce', '#ffffff')),
  '">',
  '<td><a href="', item()?['Link'], '">#', string(item()?['ID']), ' – ', item()?['Title'], '</a></td>',
  '<td>', item()?['Status'], '</td>',
  '<td>', item()?['Requester'], '</td>',
  '<td>', item()?['Vendor'], '<br/><small>PO ', item()?['PO'], '</small></td>',
  '<td>', item()?['Ordered'], '</td>',
  '<td>', item()?['Due'], if(item()?['Revised'], ' <small>(revised)</small>', ''), '</td>',
  '<td><b>',
    if(greater(item()?['DaysLate'], 0), concat(string(item()?['DaysLate']), ' days late'),
      if(not(item()?['HasDue']), 'No ETA',
        if(equals(item()?['DaysLate'], 0), 'Due today', concat('in ', string(mul(-1, item()?['DaysLate'])), ' days')))),
  '</b></td>',
  '<td>', item()?['Tracking'], '</td>',
  '</tr>'
)
```

### 9. Send an email (V2) – **Delivery Digest**

| Field | Value |
|---|---|
| To | `InventoryEmail` variable |
| CC | `@{if(greater(length(body('Chase_List')), 0), variables('FinanceEmail'), '')}` |
| Subject | `Delivery tracker: @{length(body('Deliveries'))} open order(s)@{if(greater(length(body('Overdue')), 0), concat(' – ', string(length(body('Overdue'))), ' overdue'), '')}` |
| Importance | `@{if(greater(length(body('Overdue')), 0), 'High', 'Normal')}` |
| Body | *(code view)* |

```html
<p>Good morning,</p>
<p>Orders placed and awaiting delivery, most late first.
<span style="background:#fde7e9">&nbsp;Red&nbsp;</span> = past due date,
<span style="background:#fff4ce">&nbsp;Amber&nbsp;</span> = due within @{variables('DueSoonDays')} days or no expected date.</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc;font-family:Segoe UI,Arial,sans-serif;font-size:13px">
  <tr style="background:#f3f2f1;text-align:left">
    <th>Request</th><th>Status</th><th>Requester</th><th>Vendor / PO</th><th>Ordered</th><th>Due</th><th>Timing</th><th>Carrier / tracking</th>
  </tr>
  @{join(body('Delivery_Rows'), '')}
</table>
<p>Open: <b>@{length(body('Deliveries'))}</b> &nbsp;|&nbsp; Overdue: <b>@{length(body('Overdue'))}</b>
&nbsp;|&nbsp; @{variables('ChaseAfterDays')}+ days late (Finance copied): <b>@{length(body('Chase_List'))}</b></p>
<p>Update an order: open it → <b>Edit</b> → set Status <i>In Transit</i> / <i>Delayed</i> (with revised date and reason)
/ <i>Received</i>. Add a note in <b>Delivery Updates</b> to keep a tracking history.</p>
```

### 10. (Optional) Auto-flag overdue orders as Delayed

After the email, add a **Condition** `AutoFlagDelayed` is equal to `true`,
and in *If yes* an **Apply to each** over `@{body('To_Auto_Flag')}` –
rename it **Flag Delayed** – containing **Update item**:

| Field | Value |
|---|---|
| Id | `@{items('Flag_Delayed')?['ID']}` |
| Title | `@{items('Flag_Delayed')?['Title']}` |
| Status Value | `Delayed` |
| Delay Reason | `Past the expected delivery date (@{items('Flag_Delayed')?['Due']}) – flagged automatically. Inventory to confirm new date with vendor.` |
| Delivery Updates | `Auto-flagged as delayed by the delivery tracker (@{items('Flag_Delayed')?['DaysLate']} days late).` |

Each update fires **PR-04**, which emails the requester (copying Finance)
once. When the inventory manager later enters a *Revised Delivery Date*,
PR-04 sends one updated notice.

## Notes

* The digest runs before the Finance reminder (09:00) so the two emails
  don't arrive together. Adjust as you like.
* Orders with **no expected date** stay amber every day until someone fills
  one in, which keeps ETAs from being forgotten.
* To track more than 500 open orders, turn on **Pagination** in *Get Open
  Orders* settings.
