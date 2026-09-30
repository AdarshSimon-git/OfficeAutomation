# 10 – Flow PR-06: Merge Duplicate Requests

When two requests are really for the same thing (e.g. two people in a team
each asked for the same software licences), Finance can **merge the
duplicate into the other request**. The merge only happens once the
**requester(s) approve it**.

**Trigger:** Finance fills in **Merge Into Request #** on the duplicate and saves.
**Result:**

1. The flow checks the merge makes sense. If not, it's marked *Invalid*
   and Finance is told why.
2. The **requester of the duplicate** gets an approval request in Outlook
   and Teams, explaining the merge. If the other request belongs to someone
   else, **they must approve too**, since their request will change.
3. **If everyone approves:**
   * **the surviving ("target") request**: with the default mode *Combine
     quantities and cost*, the duplicate's quantity and estimated cost are
     added to it. *Merged Requests* records `#<id> <requester> (qty n)`,
     and the duplicate's requester is added to its *Additional
     Recipients*, so they get every later email about it (ordered, delayed,
     received);
   * **the duplicate**: *Status = Merged*, *Merge State = Merged*. It drops
     out of all reminders and trackers. Its requester still sees it in
     *My Requests*, with *Merge Into Request #* showing where it went;
   * both requesters and Finance get a confirmation email.
4. **If anyone rejects, or nobody responds within 7 days:** *Merge State =
   Declined*, *Merge Into* is cleared, and Finance is emailed with the
   comments. Both requests carry on as before.

### Rules the flow enforces

* **Both requests must be *Approved - Pending Purchase*.** Each was
  approved by the CEO, so the combined request needs no new CEO approval,
  and nothing has been ordered yet. To merge while a request is still
  pending CEO approval, have the CEO reject the duplicate instead.
* The target must exist, can't be the same request, and must not itself be
  in the middle of a merge.
* **Merge Mode**:
  * `Combine quantities and cost` (default): the target's quantity and
    estimate increase.
  * `Exact duplicate - keep target unchanged`: for when the *same* need was
    submitted twice (e.g. by a manager and a team member). The duplicate
    is closed without changing the target's quantity.

```
When an item is created or modified  (trigger: Merge Into set AND Merge State not Awaiting/Merged)
├─ Initialize variable  FinanceEmail
├─ Get items            Find Target               (ID eq Merge Into)
├─ Compose              Validation Error          ('' when OK)
├─ Condition            Valid?
│   ├─ No:  Update item (Invalid, clear Merge Into) → Email Finance → Terminate
│   └─ Yes: Update item (Awaiting Requester Approval)
│           → Compose Approvers → Start and wait for an approval  Requester Merge Approval (7 days)
│           → Condition Merge Approved?
│               ├─ Yes: Update item Target → Update item Duplicate (Merged) → Email everyone
│               └─ No:  Update item Duplicate (Declined, clear Merge Into) → Email Finance
│           (+ parallel: on approval timeout → same as No)
```

## Spotting duplicates

* **Pending Purchase by Supplier** view: requests are grouped by supplier
  and sorted by title, so duplicates sit next to each other.
* **Pending Purchase** view: sort by *Item / Service Requested*, or filter
  by *Project*.
* Use **Merge Into** on the one you want to close, pointing at the one you
  want to keep (usually the older one, or the one with the better
  description).

## Build it

**Create → Automated cloud flow**, name it `PR-06 Merge Duplicate Requests`,
with the SharePoint trigger **When an item is created or modified** on
*Purchase Requests*.

### 1. Trigger condition (one line)

```
@and(not(empty(triggerOutputs()?['body/MergeInto'])), not(equals(triggerOutputs()?['body/MergeState/Value'], 'Awaiting Requester Approval')), not(equals(triggerOutputs()?['body/MergeState/Value'], 'Merged')))
```

This fires once when Finance sets *Merge Into*. It doesn't fire again for
the flow's own updates, because those either set the state to *Awaiting* /
*Merged* or clear *Merge Into*. After a *Declined* or *Invalid* merge,
Finance can simply fill in *Merge Into* again.

### 2. Initialize variable – `FinanceEmail` (String)

### 3. Get items – "Find Target"

List *Purchase Requests*, Filter Query `ID eq @{triggerOutputs()?['body/MergeInto']}`, Top Count `1`.

### 4. Compose – "Validation Error"

```
if(equals(length(outputs('Find_Target')?['body/value']), 0),
  concat('Request #', string(triggerOutputs()?['body/MergeInto']), ' does not exist.'),
if(equals(int(triggerOutputs()?['body/MergeInto']), int(triggerOutputs()?['body/ID'])),
  'A request cannot be merged into itself.',
if(not(equals(triggerOutputs()?['body/RequestStatus/Value'], 'Approved - Pending Purchase')),
  concat('This request is "', triggerOutputs()?['body/RequestStatus/Value'], '". Only requests that are Approved - Pending Purchase can be merged.'),
if(not(equals(first(outputs('Find_Target')?['body/value'])?['RequestStatus']?['Value'], 'Approved - Pending Purchase')),
  concat('Target request #', string(triggerOutputs()?['body/MergeInto']), ' is "', first(outputs('Find_Target')?['body/value'])?['RequestStatus']?['Value'], '". It must be Approved - Pending Purchase.'),
if(not(empty(first(outputs('Find_Target')?['body/value'])?['MergeInto'])),
  concat('Target request #', string(triggerOutputs()?['body/MergeInto']), ' is itself being merged into another request.'),
'')))))
```

### 5. Condition – "Valid?"

`@{outputs('Validation_Error')}` **is equal to** (leave empty).

#### If no

* **Update item – "Mark Invalid"**: Id/Title from trigger; Status Value =
  trigger `RequestStatus Value` (dynamic content, so it stays unchanged);
  **Merge State Value** `Invalid`; **Merge Into** expression `null`.
* **Send an email (V2)** to `@{triggerOutputs()?['body/Editor/Email']}`, CC
  `FinanceEmail`. Subject `Merge not possible: request #@{triggerOutputs()?['body/ID']}`,
  body `@{outputs('Validation_Error')}`.
* **Terminate**, status *Succeeded*.

#### If yes

**5a. Compose – "Target"**: `first(outputs('Find_Target')?['body/value'])`

**5b. Update item – "Mark Awaiting"**: Id/Title from trigger; Status Value
`Approved - Pending Purchase`; **Merge State Value** `Awaiting Requester Approval`.

**5c. Compose – "Approvers"**: the duplicate's requester, plus the target's
requester if they're a different person:

```
if(equals(toLower(triggerOutputs()?['body/Author/Email']), toLower(outputs('Target')?['Author']?['Email'])),
  triggerOutputs()?['body/Author/Email'],
  concat(triggerOutputs()?['body/Author/Email'], ';', outputs('Target')?['Author']?['Email']))
```

**5d. Start and wait for an approval – "Requester Merge Approval"**

| Field | Value |
|---|---|
| Approval type | **Approve/Reject – Everyone must approve** |
| Title | `Finance proposes merging purchase request #@{triggerOutputs()?['body/ID']} into #@{outputs('Target')?['ID']}` |
| Assigned to | `@{outputs('Approvers')}` |
| Item link | `@{outputs('Target')?['{Link}']}` (requesters can open this only if it's their own request; the details below have everything they need) |
| Requestor | `@{triggerOutputs()?['body/Editor/Email']}` |
| Details | *(below)* |

```markdown
Finance has found two purchase requests that look like duplicates and proposes combining them into **one order**.

| | Request to close | Request to keep |
|---|---|---|
| **Number** | #@{triggerOutputs()?['body/ID']} | #@{outputs('Target')?['ID']} |
| **Item** | @{triggerOutputs()?['body/Title']} | @{outputs('Target')?['Title']} |
| **Requested by** | @{triggerOutputs()?['body/Author/DisplayName']} | @{outputs('Target')?['Author']?['DisplayName']} |
| **Quantity** | @{triggerOutputs()?['body/Quantity']} | @{outputs('Target')?['Quantity']} |
| **Estimated cost** | @{triggerOutputs()?['body/EstimatedCost']} | @{outputs('Target')?['EstimatedCost']} |
| **Project** | @{coalesce(triggerOutputs()?['body/Project/Value'], '–')} | @{coalesce(outputs('Target')?['Project']?['Value'], '–')} |

**Merge mode:** @{coalesce(triggerOutputs()?['body/MergeMode/Value'], 'Combine quantities and cost')}

@{if(equals(triggerOutputs()?['body/MergeMode/Value'], 'Exact duplicate - keep target unchanged'), concat('Request #', string(outputs('Target')?['ID']), ' stays as it is. Request #', string(triggerOutputs()?['body/ID']), ' is closed as a duplicate.'), concat('Request #', string(outputs('Target')?['ID']), ' will become quantity ', string(add(int(coalesce(outputs('Target')?['Quantity'], 0)), int(coalesce(triggerOutputs()?['body/Quantity'], 0)))), '. Request #', string(triggerOutputs()?['body/ID']), ' is closed.'))}

Everyone involved keeps getting email updates (ordered, delayed, received) for the combined request.

**Finance notes:** @{triggerOutputs()?['body/FinanceNotes']}
```

Settings → **Timeout** `P7D`.

**5e. Condition – "Merge Approved?"**: `@{outputs('Requester_Merge_Approval')?['body/outcome']}` is equal to `Approve`.

##### If yes

**Compose – "Combine"**: `@{not(equals(triggerOutputs()?['body/MergeMode/Value'], 'Exact duplicate - keep target unchanged'))}`

**Update item – "Update Target"**

| Field | Value |
|---|---|
| Id | `@{outputs('Target')?['ID']}` |
| Title | `@{outputs('Target')?['Title']}` |
| Status Value | `Approved - Pending Purchase` |
| Quantity | `@{if(outputs('Combine'), add(int(coalesce(outputs('Target')?['Quantity'], 0)), int(coalesce(triggerOutputs()?['body/Quantity'], 0))), outputs('Target')?['Quantity'])}` |
| Estimated Total Cost | `@{if(outputs('Combine'), add(float(coalesce(outputs('Target')?['EstimatedCost'], 0)), float(coalesce(triggerOutputs()?['body/EstimatedCost'], 0))), outputs('Target')?['EstimatedCost'])}` |
| Merged Requests | `@{concat(coalesce(outputs('Target')?['MergedRequests'], ''), '#', string(triggerOutputs()?['body/ID']), ' ', triggerOutputs()?['body/Author/DisplayName'], ' (qty ', string(triggerOutputs()?['body/Quantity']), ', ', if(outputs('Combine'), 'combined', 'duplicate'), '); ')}` |
| Additional Recipients | `@{concat(coalesce(outputs('Target')?['AdditionalRecipients'], ''), if(equals(toLower(triggerOutputs()?['body/Author/Email']), toLower(outputs('Target')?['Author']?['Email'])), '', concat(triggerOutputs()?['body/Author/Email'], ';')), coalesce(triggerOutputs()?['body/AdditionalRecipients'], ''))}` |
| Finance Notes | `@{concat(coalesce(outputs('Target')?['FinanceNotes'], ''), decodeUriComponent('%0A'), 'Merged #', string(triggerOutputs()?['body/ID']), ' on ', formatDateTime(utcNow(), 'dd MMM yyyy'), ' – approved by requester(s).')}` |

The last part of *Additional Recipients* carries over anyone already merged
*into* the duplicate, so chains of merges keep everyone informed.

**Update item – "Close Duplicate"**

| Field | Value |
|---|---|
| Id / Title | trigger `ID` / `Title` |
| Status Value | `Merged` |
| Merge State Value | `Merged` |
| Finance Notes | `@{concat(coalesce(triggerOutputs()?['body/FinanceNotes'], ''), decodeUriComponent('%0A'), 'Merged into #', string(outputs('Target')?['ID']), ' on ', formatDateTime(utcNow(), 'dd MMM yyyy'), '.')}` |

**Send an email (V2) – "Email Merge Done"**

| Field | Value |
|---|---|
| To | `@{outputs('Approvers')}` |
| CC | `FinanceEmail` |
| Subject | `Merged: purchase request #@{triggerOutputs()?['body/ID']} is now part of #@{outputs('Target')?['ID']}` |
| Body | `<p>Request <b>#@{triggerOutputs()?['body/ID']}</b> (@{triggerOutputs()?['body/Title']}) has been merged into <b>#@{outputs('Target')?['ID']}</b> (@{outputs('Target')?['Title']}).</p><p>You'll receive all further updates – ordered, delayed and received – for #@{outputs('Target')?['ID']}.</p>` |

##### If no

**Update item – "Mark Declined"**: Id/Title from trigger; Status Value
`Approved - Pending Purchase`; Merge State Value `Declined`; Merge Into
`null` (expression).

**Send an email (V2)** to `FinanceEmail` (and the trigger's `Editor/Email`):
subject `Merge declined: #@{triggerOutputs()?['body/ID']} → #@{outputs('Target')?['ID']}`. In the body,
include who responded and their comments. The first response is
`@{outputs('Requester_Merge_Approval')?['body/responses']?[0]?['responder']?['displayName']}` /
`@{outputs('Requester_Merge_Approval')?['body/responses']?[0]?['comments']}`, and use `?[1]` for the second
approver when there are two.

**Timeout branch:** as in PR-01, add a parallel branch after *Requester
Merge Approval* with the same two actions, *Configure run after* → **has
timed out / has failed**. In the email, say that the requester(s) didn't
respond within 7 days.

## Teams thread

Post the merge proposal and outcome into both requests' threads. See
[12 – Teams channel](12-teams-channel.md#pr-06-merge-duplicate-requests-10).

## Other flows updated for merges

* **Status `Merged`** isn't in any reminder filter, so merged duplicates
  drop out of PR-03 and PR-05 automatically.
* **PR-02 and PR-04** send requester emails to
  `Author` + **Additional Recipients**, so people whose request was merged
  still get notified. See the *To* fields in [03](03-flow-order-placed.md)
  and [05](05-flow-delivery-updates.md).
