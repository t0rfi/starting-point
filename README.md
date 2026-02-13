# Ralph Starting Point

A minimal starting point for using Ralph, an autonomous coding agent that implements features from a PRD (Product Requirements Document) one user story at a time.

## What is Ralph?

Ralph is an autonomous coding agent that:
- Reads a structured PRD (`prd.json`) containing features and user stories
- Implements one story at a time, running quality checks after each
- Creates PRs for features and updates them as stories are completed
- Tracks progress and learns patterns as it works

This repository provides the scaffolding to get Ralph running on your own projects.

## Prerequisites

- [Claude Code CLI](https://claude.com/claude-code) installed
- Git configured with access to push to your repository

## Getting Started

### Step 1: Run Claude with permissions skipped

```bash
claude --dangerously-skip-permissions
```

This flag allows Claude to run autonomously without prompting for permission on each file edit or command. Required for Ralph's autonomous operation.

### Step 2: Invoke the /prd skill

Once Claude is running, manually type:

```
/prd
```

This starts the PRD generation process.

### Step 3: Describe your application

When prompted, describe the application you want to build. Here's a sample description you can use for testing:

> A web-based personal task manager that allows users to:
> - Add tasks with titles, descriptions, due dates, and priorities
> - Organize tasks into categories/projects
> - Mark tasks as complete
> - List and filter tasks by status, category, or due date
> - Uses React for the frontend and Express with SQLite for the backend

**Important:** Tell Claude to ONLY create `prd.md` - no `prd.json`, no implementation yet.

### Step 4: Answer PRD questions

The `/prd` skill will ask clarifying questions about your application. Answer them to refine the requirements.

### Step 5: Clear context

After `prd.md` is created, clear the conversation to start fresh:

```
/clear
```

### Step 6: Invoke the /ralph skill

Type:

```
/ralph
```

This converts your PRD into the structured JSON format Ralph needs.

### Step 7: Create prd.json only

**Important:** Tell Claude to create `prd.json` only - no implementation. Ralph will handle the implementation autonomously.

### Step 8: Exit Claude

Once `prd.json` is created (and optionally `progress.txt`), exit Claude:

```
/exit
```

### Step 9: Run ralph.sh

Start Ralph's autonomous loop:

```bash
./ralph.sh --tool claude [max_iterations]
```

Where `max_iterations` is the number of user stories in your first feature. For example, if your first feature has 5 stories:

```bash
./ralph.sh --tool claude 5
```

### Step 10: Watch Ralph work

Ralph will now autonomously:
1. Read the PRD and find the first incomplete story
2. Implement the story
3. Run quality checks
4. Commit the changes
5. Create or update the PR
6. Move to the next story

You can monitor progress in:
- `progress.txt` - Detailed log of what was implemented
- `prd.json` - Story completion status updates
- GitHub PRs - Feature progress and test plans

## Project Structure

```
.
├── CLAUDE.md      # Instructions for Ralph (don't modify)
├── ralph.sh       # Autonomous loop runner
├── prd.json       # Your PRD (created via /ralph skill)
├── prd.md         # Human-readable PRD (created via /prd skill)
└── progress.txt   # Ralph's progress log (auto-generated)
```

## Tips

- Start with a small first feature (3-5 stories) to test the workflow
- Review PRs as Ralph creates them - you can provide feedback
- Check `progress.txt` for insights into what Ralph learned about your codebase
