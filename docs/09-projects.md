# 09 – Linking purchases to projects

Every purchase request can be linked to a **project**, so you can see what
each project is spending and the CEO can see the project's budget position
when approving.

## What's included

| Piece | What it does |
|---|---|
| **Projects** list | One row per project: *Project* (name), *Project Code*, *Project Manager*, *Budget*, *Project Status* (Active / On Hold / Closed). The script creates it with a catch-all **GEN - General / Overhead** project. |
| **Project** column on Purchase Requests | A lookup that requesters pick on the new-request form |
| **By Project** view | Requests grouped by project, with totals of *Estimated Total Cost* and *Actual Cost*. Rejected, expired, cancelled and merged requests are excluded. |
| PR-01 budget check (optional, below) | Adds the project's budget, committed spend and remaining budget to the CEO's approval request, and warns if the project is closed or would go over budget |

## Managing projects

* Finance, the CEO and Inventory (the *Purchase Request Managers* group)
  can add and edit projects. Everyone else can only read them, which lets
  them pick one.
* **Naming tip:** start the project name with its code, e.g. `PRJ-014 –
  Office fit-out`. The dropdown on the request form shows the name, so
  people can search by code.
* **Closing a project:** set *Project Status = Closed*. SharePoint lookups
  can't hide closed items from the dropdown, so the budget check below
  warns the CEO if someone picks a closed project. You can also rename it
  to start with `[CLOSED]`.
* The project link isn't required on the list (making it required would
  force every flow's *Update item* action to supply it). Tell staff to use
  **GEN** when a purchase isn't for a specific project. The budget check
  flags requests with no project.

## Add the project to emails

In PR-01 ([02](02-flow-ceo-approval.md)), add this line to the approval
**Details** and the Finance email table:

```
**Project:** @{coalesce(triggerOutputs()?['body/Project/Value'], 'Not specified')}
```

```html
<tr><td><b>Project</b></td><td>@{coalesce(triggerOutputs()?['body/Project/Value'], 'Not specified')}</td></tr>
```

PR-02 and PR-07 already include the project in their emails.

## Optional: budget check in the CEO approval (PR-01)

Add these actions to PR-01 **between *Mark Pending Approval* and *CEO
Approval***.

**1. Condition – "Has Project?"**:
`@{triggerOutputs()?['body/Project/Id']}` *is not equal to* (leave blank),
or in advanced mode `@not(empty(triggerOutputs()?['body/Project/Id']))`.

Inside **If yes**:

**2. SharePoint *Get item* – "Get Project"**: List `Projects`, Id
`@{triggerOutputs()?['body/Project/Id']}`.

**3. SharePoint *Get items* – "Project Commitments"**: List `Purchase
Requests`, Filter Query:

```
ProjectId eq @{triggerOutputs()?['body/Project/Id']} and ID ne @{triggerOutputs()?['body/ID']} and (RequestStatus eq 'Approved - Pending Purchase' or RequestStatus eq 'Purchased' or RequestStatus eq 'In Transit' or RequestStatus eq 'Delayed' or RequestStatus eq 'Partially Received' or RequestStatus eq 'Received')
```

Top Count `5000`, with Pagination on (Settings).

**4. Select – "Commitment Amounts"**: From `@{outputs('Project_Commitments')?['body/value']}`,
Map in **text mode**: `float(coalesce(item()?['ActualCost'], item()?['EstimatedCost'], 0))`.
This uses the actual cost once known, otherwise the estimate.

**5. Compose – "Committed Spend"** (sums the array; Power Automate has no
`sum()` function, so this uses the XPath trick):

```
xpath(xml(json(concat('{"r":{"v":', string(body('Commitment_Amounts')), '}}'))), 'sum(/r/v)')
```

**6. Compose – "Budget Summary"**:

```
concat(
  '**Project:** ', outputs('Get_Project')?['body/Title'],
  if(equals(outputs('Get_Project')?['body/ProjectStatus/Value'], 'Active'), '', concat(' ⚠️ **Project is ', outputs('Get_Project')?['body/ProjectStatus/Value'], '**')),
  decodeUriComponent('%0A%0A'),
  if(empty(outputs('Get_Project')?['body/Budget']),
    '**Budget:** not set',
    concat(
      '**Budget:** ', formatNumber(float(outputs('Get_Project')?['body/Budget']), 'N2'),
      ' | **Already committed:** ', formatNumber(float(outputs('Committed_Spend')), 'N2'),
      ' | **Remaining after this request:** ', formatNumber(sub(sub(float(outputs('Get_Project')?['body/Budget']), float(outputs('Committed_Spend'))), float(coalesce(triggerOutputs()?['body/EstimatedCost'], 0))), 'N2'),
      if(less(sub(sub(float(outputs('Get_Project')?['body/Budget']), float(outputs('Committed_Spend'))), float(coalesce(triggerOutputs()?['body/EstimatedCost'], 0))), 0), ' ⚠️ **Over budget**', '')
    )
  )
)
```

In **If no** (no project): **Compose – "No Project Summary"** with
`**Project:** ⚠️ none selected`.

**7.** At the top of the *CEO Approval* **Details**, add:

```
@{coalesce(outputs('Budget_Summary'), outputs('No_Project_Summary'))}
```

(The Compose that didn't run returns null, so `coalesce` picks the one that
did.)

**8. (Optional)** CC the project manager on the Finance email:
`@{outputs('Get_Project')?['body/ProjectManager/Email']}`.

> If *Project Commitments* returns an error about the filter, your tenant
> may need the alternative lookup syntax `Project/Id eq …` instead of
> `ProjectId eq …`.

## Reporting

* **By Project** view: expand a group to see each request, with totals at
  the top.
* **Excel:** from the view, **Export → Export to Excel** and pivot by
  *Project* and *Supplier*.
* **Power BI:** connect to the SharePoint list (*Get data → SharePoint Online
  list*) for budget-vs-actual dashboards per project.
