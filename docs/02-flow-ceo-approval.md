# 02 – Flow PR-01: Submit & CEO Approval

**Trigger:** a new item in *Purchase Requests*
**Result:** the CEO approves or rejects it. Approved requests go to Finance;
the requester is told the outcome either way.

```
When an item is created
├─ Initialize variable  CEOEmail
├─ Initialize variable  FinanceEmail
├─ Teams: @mention CEO + Post Request Thread       (see doc 12)
├─ Update item          Mark Pending Approval
├─ Start and wait for an approval   CEO Approval        (timeout 28 days)
├─ Condition            Approved?                        (runs if CEO Approval succeeded)
│   ├─ Yes: Update item (Approved) → Email Finance → Email requester → [Teams reply]
│   └─ No:  Update item (Rejected) → Email requester
└─ Update item          Mark Expired → Email requester   (runs if CEO Approval timed out/failed)
```

> **Name the actions exactly as shown** (click `…` → *Rename*). The
> expressions refer to actions by name, with spaces replaced by underscores:
> `CEO Approval` becomes `outputs('CEO_Approval')`.

## Build it

In [make.powerautomate.com](https://make.powerautomate.com): **Create →
Automated cloud flow**, name it `PR-01 Submit & CEO Approval`, and pick the
SharePoint trigger **When an item is created**.

### 1. Trigger – *When an item is created*

| Field | Value |
|---|---|
| Site Address | your site, e.g. `https://yourorg.sharepoint.com/sites/Operations` |
| List Name | `Purchase Requests` |

### 2. Initialize variable – `CEOEmail`
Type **String**, value `ceo@yourorg.com`.

### 3. Initialize variable – `FinanceEmail`
Type **String**, value `finance@yourorg.com` (a distribution list or shared
mailbox is best, so the flow doesn't need editing when staff change).

### 4. SharePoint *Update item* – rename to **Mark Pending Approval**

| Field | Value |
|---|---|
| Site Address / List Name | same as trigger |
| Id | `ID` (dynamic content from the trigger) |
| Item / Service Requested (Title) | `Title` (dynamic content, required by the connector) |
| Status Value | `Pending CEO Approval` |
| Reminders Sent | `0` |
| Completion Notified | `No` |
| Received Notified | `No` |

### 5. Approvals *Start and wait for an approval* – rename to **CEO Approval**

| Field | Value |
|---|---|
| Approval type | **Approve/Reject – First to respond** |
| Title | `Purchase request #@{triggerOutputs()?['body/ID']}: @{triggerOutputs()?['body/Title']}` |
| Assigned to | `CEOEmail` variable |
| Details | *(Markdown, see below)* |
| Item link | `@{triggerOutputs()?['body/{Link}']}` |
| Item link description | `Open request in SharePoint` |
| Requestor | `@{triggerOutputs()?['body/Author/Email']}` |

Paste the **Details** below. You can type it with dynamic content, or paste
it as is: the `@{...}` expressions are evaluated when pasted into the field.

```markdown
**Requested by:** @{triggerOutputs()?['body/Author/DisplayName']} – @{triggerOutputs()?['body/Department/Value']}

**Item / service:** @{triggerOutputs()?['body/Title']}

**Project:** @{coalesce(triggerOutputs()?['body/Project/Value'], 'Not specified')}

**Quantity:** @{triggerOutputs()?['body/Quantity']}

**Estimated total cost:** @{triggerOutputs()?['body/EstimatedCost']}

**Urgency:** @{triggerOutputs()?['body/Urgency/Value']}

**Needed by:** @{if(empty(triggerOutputs()?['body/NeededBy']), 'Not specified', formatDateTime(coalesce(triggerOutputs()?['body/NeededBy'], utcNow()), 'dd MMM yyyy'))}

**Suggested vendor:** @{triggerOutputs()?['body/Vendor']}

**Description:**
@{triggerOutputs()?['body/ItemDescription']}

**Business justification:**
@{triggerOutputs()?['body/Justification']}
```

> **Optional budget check:** to show the CEO the project's budget, committed
> spend and remaining budget in this approval, add the steps in
> [09 – Projects](09-projects.md#optional-budget-check-in-the-ceo-approval-pr-01).

**Settings** (`…` → *Settings*) → **Timeout**: `P28D`.
Flow runs have a hard 30-day limit, so the timeout makes the flow end
cleanly (with *Approval Expired*) instead of failing silently. PR-03 nudges
the CEO long before that.

### 6. Condition – rename to **Approved?**

`@{outputs('CEO_Approval')?['body/outcome']}` **is equal to** `Approve`

#### If yes

**6a. Update item – "Mark Approved"**

| Field | Value |
|---|---|
| Id | trigger `ID` |
| Title | trigger `Title` |
| Status Value | `Approved - Pending Purchase` |
| CEO Comments | `@{outputs('CEO_Approval')?['body/responses']?[0]?['comments']}` |
| CEO Decision Date | `@{outputs('CEO_Approval')?['body/completionDate']}` |

**6b. Office 365 Outlook *Send an email (V2)* – "Email Finance"**

| Field | Value |
|---|---|
| To | `FinanceEmail` variable |
| Subject | `Action needed: approved purchase #@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}` |
| Importance | `High` if you want; otherwise Normal |
| Body | *(click `</>` to switch to code view, then paste)* |

```html
<p>Hello Finance team,</p>
<p>The CEO has <b>approved</b> the following purchase request. Please make the purchase and then
open the request, click <b>Edit</b> and set <b>Status = Purchased</b> (add the PO / invoice number, actual cost and expected delivery date).</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc">
  <tr><td><b>Request</b></td><td>#@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}</td></tr>
  <tr><td><b>Requested by</b></td><td>@{triggerOutputs()?['body/Author/DisplayName']} (@{triggerOutputs()?['body/Department/Value']})</td></tr>
  <tr><td><b>Project</b></td><td>@{coalesce(triggerOutputs()?['body/Project/Value'], 'Not specified')}</td></tr>
  <tr><td><b>Quantity</b></td><td>@{triggerOutputs()?['body/Quantity']}</td></tr>
  <tr><td><b>Estimated cost</b></td><td>@{triggerOutputs()?['body/EstimatedCost']}</td></tr>
  <tr><td><b>Suggested vendor</b></td><td>@{triggerOutputs()?['body/Vendor']}</td></tr>
  <tr><td><b>Needed by</b></td><td>@{if(empty(triggerOutputs()?['body/NeededBy']), 'Not specified', formatDateTime(coalesce(triggerOutputs()?['body/NeededBy'], utcNow()), 'dd MMM yyyy'))}</td></tr>
  <tr><td><b>Urgency</b></td><td>@{triggerOutputs()?['body/Urgency/Value']}</td></tr>
  <tr><td><b>CEO comments</b></td><td>@{outputs('CEO_Approval')?['body/responses']?[0]?['comments']}</td></tr>
</table>
<p><a href="@{triggerOutputs()?['body/{Link}']}">Open the request</a></p>
<p>You'll get a daily reminder until it's marked as Purchased.</p>
```

**6c. Teams thread.** Each request is posted to the *Purchase Requests*
Teams channel, and the decision is posted as a reply. The steps (posting
the thread before *Mark Pending Approval*, and a reply at the end of each
branch) are in [12 – Teams channel](12-teams-channel.md#pr-01-submit--ceo-approval-02).

**6d. Send an email (V2) – "Email Requester Approved"**

| Field | Value |
|---|---|
| To | `@{triggerOutputs()?['body/Author/Email']}` |
| Subject | `Approved: your purchase request #@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}` |
| Body | `<p>Good news – the CEO approved your request. Finance has been notified and will let you know when it's purchased.</p><p><b>CEO comments:</b> @{outputs('CEO_Approval')?['body/responses']?[0]?['comments']}</p><p><a href="@{triggerOutputs()?['body/{Link}']}">View request</a></p>` |

#### If no

**6e. Update item – "Mark Rejected"**: Id, Title as above; Status Value
`Rejected`; CEO Comments and CEO Decision Date as in 6a.

**6f. Send an email (V2) – "Email Requester Rejected"**

| Field | Value |
|---|---|
| To | `@{triggerOutputs()?['body/Author/Email']}` |
| Subject | `Not approved: purchase request #@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}` |
| Body | `<p>Your purchase request was not approved by the CEO.</p><p><b>Comments:</b> @{outputs('CEO_Approval')?['body/responses']?[0]?['comments']}</p><p>If you'd like to change and resubmit it, create a new request.</p><p><a href="@{triggerOutputs()?['body/{Link}']}">View request</a></p>` |

### 7. Timeout handling (a parallel branch after *CEO Approval*)

Hover the arrow between **CEO Approval** and **Approved?** → **+ → Add a
parallel branch**, then add:

**7a. Update item – "Mark Expired"**: Id, Title; Status Value `Approval Expired`.
`…` → **Configure run after** → untick *is successful*, tick **has timed
out** and **has failed**.

**7b. Send an email (V2) – "Email Requester Expired"** (runs after 7a
succeeds): tell the requester that the approval expired and that they
should resubmit if the purchase is still needed. CC `CEOEmail` if you want.

The *Approved?* condition keeps its default run after (*is successful*), so
exactly one branch runs.

## Save and test

Save, then create a test item in the list. Within about a minute the CEO
(use your own address while testing) should get the approval in Outlook and
in the Teams **Approvals** app.
