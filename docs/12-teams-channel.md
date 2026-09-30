# 12 – Teams channel: one thread per request

Every purchase request gets its **own thread** in a shared Teams channel.
The first post shows the request and @mentions the CEO. Every later event
(CEO decision, merge, order placed, delay, received) is posted as a **reply
in the same thread**. The CEO, Finance and Inventory can then discuss a
request right under it, and anyone can scroll one thread to see its whole
history.

```
#purchase-requests
└─ 🆕 #42 Dell 27" monitor ×2 – ₹38,000 – Asha (IT) – Project PRJ-014   @CEO
     ├─ CEO: "Do we need two? Asha, can you confirm?"            ← people discuss here
     ├─ Asha's manager: "Yes – one for the new joiner."
     ├─ ✅ Approved by CEO – "OK, go ahead"                       ← PR-01
     ├─ 🛒 Ordered – PO 4471 from Dell India, expected 12 Oct      ← PR-02
     ├─ ⏰ Delayed – new date 16 Oct (courier backlog)             ← PR-04
     └─ 📦 Received ×2 by Ravi – good condition                    ← PR-04
```

**The CEO still approves with the Approve/Reject buttons** in the Teams
**Approvals** app (or Outlook, or the mobile app). The thread is for context
and discussion, and the decision is posted back into it automatically. This
keeps the Approvals audit trail and makes sure only the CEO can approve.

## 1. Create the team and channel

1. In Teams, use an existing team that contains the **CEO, Finance and
   Inventory** (e.g. *Management* or *Operations*), or create one.
2. Add a **standard** channel called **Purchase Requests**. Everyone in the
   team can see it. A standard channel is the safest choice: the
   Power Automate Teams connector fully supports standard channels, while
   support for Teams *shared*- and *private*-type channels is more limited.
3. Optional: add a **Lists** tab to the channel showing the *Purchase
   Requests* list (*Pending Purchase* view), and a second one for *Awaiting
   Delivery*.
4. Channel settings → **Notifications**: suggest the CEO sets *All new
   posts* for this channel. The @mention notifies them either way.

**Requesters are not in this channel** by default, because it shows
everyone's requests and costs. They keep getting their updates by email. If
your organisation is fine with open visibility, you can add everyone to the
team instead.

## 2. Add the list column

The script adds a hidden **Teams Thread ID** column (`TeamsThreadId`, single
line of text, hidden on both forms). If you set the list up by hand, add it
yourself. It stores the ID of each request's first post so later flows can
reply to it.

## 3. Flow changes

All Teams actions use the **Microsoft Teams** connector (standard, no extra
licence) and **post as Flow bot**. The bot shows up as *Workflows* in newer
Teams, so posts don't come from a person. In each action, pick the same
**Team** and **Channel**.

> **A Teams hiccup should never block the process.** Put each reply step
> at the **end** of its branch (after the emails and updates), inside a
> **Condition "Has thread?"** with
> `@not(empty(<thread id expression>))`, which also skips requests created
> before the channel existed. If you want the flow to succeed even when
> Teams is down, set the action's **Configure run after** on anything that
> follows it to include *has failed*.

### PR-01 Submit & CEO Approval ([02](02-flow-ceo-approval.md))

**a. Before *Mark Pending Approval*, add a Teams *Get an @mention token for
a user*** (rename it **CEO Mention**). User: `CEOEmail` variable.

**b. Then a Teams *Post message in a chat or channel*** (rename it
**Post Request Thread**):

| Field | Value |
|---|---|
| Post as | Flow bot |
| Post in | Channel |
| Team / Channel | your team / *Purchase Requests* |
| Subject | `🆕 #@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}` |
| Message | *(code view `</>`, paste below)* |

```html
<p>New purchase request from <b>@{triggerOutputs()?['body/Author/DisplayName']}</b> (@{triggerOutputs()?['body/Department/Value']}) – awaiting approval by @{outputs('CEO_Mention')?['body/atMention']}</p>
<table>
<tr><td><b>Item</b></td><td>@{triggerOutputs()?['body/Title']} × @{triggerOutputs()?['body/Quantity']}</td></tr>
<tr><td><b>Estimated cost</b></td><td>@{triggerOutputs()?['body/EstimatedCost']}</td></tr>
<tr><td><b>Project</b></td><td>@{coalesce(triggerOutputs()?['body/Project/Value'], 'Not specified')}</td></tr>
<tr><td><b>Urgency</b></td><td>@{triggerOutputs()?['body/Urgency/Value']}</td></tr>
<tr><td><b>Needed by</b></td><td>@{if(empty(triggerOutputs()?['body/NeededBy']), 'Not specified', formatDateTime(coalesce(triggerOutputs()?['body/NeededBy'], utcNow()), 'dd MMM yyyy'))}</td></tr>
<tr><td><b>Justification</b></td><td>@{triggerOutputs()?['body/Justification']}</td></tr>
</table>
<p><a href="@{triggerOutputs()?['body/{Link}']}">Open request</a> · Approve or reject in the <b>Approvals</b> app. Discuss below in this thread.</p>
```

**c. In *Mark Pending Approval*, add** Teams Thread ID =
`@{outputs('Post_Request_Thread')?['body/id']}`.

Then on *Mark Pending Approval* → `…` → **Configure run after** → *Post
Request Thread*: tick **is successful, has failed, is skipped**. A Teams
problem then doesn't stop the approval; the thread ID is simply left blank
and later replies are skipped.

**d. Replace the old optional step 6c** (Teams post to Finance) with a
Teams ***Reply with a message in a channel*** at the end of each outcome
branch. Use *Post as* Flow bot, the same Team / Channel, and **Message ID**
`@{outputs('Post_Request_Thread')?['body/id']}`.

| Branch | Reply message |
|---|---|
| Approved | `✅ <b>Approved by @{outputs('CEO_Approval')?['body/responses']?[0]?['responder']?['displayName']}</b> – @{coalesce(outputs('CEO_Approval')?['body/responses']?[0]?['comments'], 'no comments')}<br/>Over to Finance to order.` |
| Rejected | `❌ <b>Rejected by @{outputs('CEO_Approval')?['body/responses']?[0]?['responder']?['displayName']}</b> – @{coalesce(outputs('CEO_Approval')?['body/responses']?[0]?['comments'], 'no comments')}` |
| Timed out (parallel branch) | `⌛ <b>Approval expired</b> after 28 days without a response. The requester has been asked to resubmit.` |

### PR-02 Order Placed ([03](03-flow-order-placed.md))

At the end, a Condition *Has thread?* on `triggerOutputs()?['body/TeamsThreadId']`,
then ***Reply with a message in a channel***, Message ID
`@{triggerOutputs()?['body/TeamsThreadId']}`:

```html
🛒 <b>Ordered</b> by @{triggerOutputs()?['body/Editor/DisplayName']} – PO <b>@{triggerOutputs()?['body/PONumber']}</b>
from @{coalesce(triggerOutputs()?['body/Supplier/Value'], triggerOutputs()?['body/Vendor'], 'supplier not set')},
expected <b>@{if(empty(triggerOutputs()?['body/ExpectedDelivery']), 'TBC', formatDateTime(coalesce(triggerOutputs()?['body/ExpectedDelivery'], utcNow()), 'dd MMM yyyy'))}</b>.
Over to Inventory to track delivery.
```

### PR-04 Delivery Updates ([05](05-flow-delivery-updates.md))

At the end of each Switch case, the same *Has thread?* condition and a
reply to `@{triggerOutputs()?['body/TeamsThreadId']}`:

| Case | Reply message |
|---|---|
| Received | `📦 <b>Received</b> – @{outputs('Stamp_Receipt')?['body/QuantityReceived']} of @{triggerOutputs()?['body/Quantity']} checked in by @{coalesce(outputs('Stamp_Receipt')?['body/ReceivedBy']?['DisplayName'], triggerOutputs()?['body/Editor/DisplayName'])}. @{coalesce(triggerOutputs()?['body/ReceiptNotes'], '')}` |
| Delayed | `⏰ <b>Delayed</b> – new date <b>@{if(empty(triggerOutputs()?['body/RevisedDelivery']), 'not yet known', formatDateTime(coalesce(triggerOutputs()?['body/RevisedDelivery'], utcNow()), 'dd MMM yyyy'))}</b>. Reason: @{coalesce(triggerOutputs()?['body/DelayReason'], 'not given')}` |

Auto-flagged delays from PR-05 go through PR-04, so they appear in the
thread too.

### PR-06 Merge Duplicate Requests ([10](10-flow-merge-duplicates.md))

Reply on the **duplicate's** thread (`triggerOutputs()?['body/TeamsThreadId']`)
and, when it's approved, also on the **target's** thread
(`outputs('Target')?['TeamsThreadId']`):

| When | Thread | Message |
|---|---|---|
| After *Mark Awaiting* | duplicate | `🔀 Finance proposes merging this into <b>#@{outputs('Target')?['ID']}</b> (@{outputs('Target')?['Title']}). Waiting for requester approval.` |
| Merge approved | duplicate | `🔀 <b>Merged</b> into #@{outputs('Target')?['ID']}. Follow that thread from now on.` |
| Merge approved | target | `🔀 Request <b>#@{triggerOutputs()?['body/ID']}</b> (@{triggerOutputs()?['body/Author/DisplayName']}, qty @{triggerOutputs()?['body/Quantity']}) was merged into this one. New quantity: @{if(outputs('Combine'), add(int(coalesce(outputs('Target')?['Quantity'], 0)), int(coalesce(triggerOutputs()?['body/Quantity'], 0))), outputs('Target')?['Quantity'])}.` |
| Declined / timed out | duplicate | `🔀 Merge into #@{outputs('Target')?['ID']} was <b>declined</b> – both requests continue separately.` |

### PR-07 Order all from this supplier ([11](11-flow-supplier-batch-order.md)) – optional

Each item marked *Purchased* already gets an 🛒 reply through PR-02. If
you'd also like a single overview post per batch, add a ***Post message in
a chat or channel*** after *Batch Summary*, with subject `📦 Batch order
@{PO Number} – @{outputs('Supplier_Details')?['body/Title']}` and the same
table as the batch summary email.

### Daily digests (optional)

PR-03 (Finance reminders) and PR-05 (delivery tracker) can also post their
digest to the channel as a **new** post each morning. Add a *Post message
in a chat or channel* next to the digest email, with the same HTML body.
Many teams prefer to keep digests in email so the channel stays one thread
per request.

## Tips for the team

* **Discuss in the thread, decide with the buttons.** A "looks fine" reply
  in the channel doesn't approve anything; only the Approvals app or email
  buttons do.
* Use **@mentions** in replies to pull people in, e.g. @Finance to ask
  about budget or @Inventory to ask about stock on hand.
* **Search** the channel for `#42` to find any request's thread.
* The thread is a discussion log. The **list is the system of record**: PO
  numbers, dates and statuses live there, and the flows read them from
  there.
