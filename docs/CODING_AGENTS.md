# Use Beztrace with coding agents

Use Codex or Claude Code locally on your Mac to turn a glyph image into JSON/SVG,
or prepare compatible masters with explicit geometry and node limits. The agent
runs the same standalone CLI you would run in Terminal. Beztrace needs no MCP
server, Python runtime or API key; the agent keeps its usual authentication and
tool permissions. These instructions cover local macOS sessions, where the
installed engine and your artwork are accessible.

## Install the engine and skills

Install the signed [engine 0.2.2](https://github.com/thierryc/beztrace/releases/tag/v0.2.2)
using the [release guide](RELEASE.md). Check from your agent's terminal:

```sh
beztrace --version
beztrace capabilities --format json
```

Expect engine version `0.2.2`. Matching requires the advertised `matchModes`;
verified fitting and joint smoothing advertise `hybridFittingVersion: 1` and
`jointSmoothingVersion: 1`. If the agent cannot find the command, use the installed
executable at `/Library/Application Support/beztrace/bin/beztrace` with the path
quoted. A source checkout is needed only to obtain the skills, not to build or
run the installed engine.

Clone this repository, or use an existing checkout, and open a terminal at its root:

```sh
git clone https://github.com/thierryc/beztrace.git
cd beztrace
```

Choose **one** destination for the copy step below.

### Codex

For skills available across your local projects:

```sh
BEZTRACE_SKILLS_DIR="$HOME/.agents/skills"
```

For one project, use that project's `.agents/skills/` directory instead.
Codex CLI and the IDE extension support `/skills` and `$skill-name` mentions;
in the desktop app, select the skill from the available skills or mention its
name in your request. See the [official OpenAI skill documentation](https://learn.chatgpt.com/docs/build-skills).

### Claude Code

For skills available across your local projects:

```sh
BEZTRACE_SKILLS_DIR="$HOME/.claude/skills"
```

For one project, use that project's `.claude/skills/` directory instead.
Invoke an installed skill with `/skill-name`. See the
[official Claude Code skill documentation](https://code.claude.com/docs/en/skills).

### Copy both skill folders

Run this in the same terminal after choosing the destination. It preserves any
existing installation; review an existing folder separately before updating it.
Copy the whole folder so its supporting references and license files stay with it.

```sh
: "${BEZTRACE_SKILLS_DIR:?Choose a skills destination first}"
mkdir -p "$BEZTRACE_SKILLS_DIR"
for skill in beztrace-vectorize-image beztrace-match-masters; do
  if [ -e "$BEZTRACE_SKILLS_DIR/$skill" ] || [ -L "$BEZTRACE_SKILLS_DIR/$skill" ]; then
    printf 'Already present; left unchanged: %s\n' "$skill"
  else
    cp -R "skills/$skill" "$BEZTRACE_SKILLS_DIR/$skill"
  fi
done
```

Start a new agent session if the skills do not appear. Installing the engine
does not automatically install skills, and copying skills does not install the
engine or grant access to Glyphs.

## Trace a glyph image

In Codex, begin with `$beztrace-vectorize-image`; in Claude Code, begin with
`/beztrace-vectorize-image`. Then give the input, output and placement:

```text
Trace artwork/A.png with Beztrace. Export review/A.json and review/A.svg.
Map the ink to y=0…700, use advance width 600 and left sidebearing 50.
Preserve the source image and show me the resulting paths before font import.
```

The corresponding CLI calls are:

```sh
mkdir -p review
beztrace trace artwork/A.png --format json --output review/A.json \
  --source-box ink --target-y-min 0 --target-y-max 700 \
  --advance 600 --lsb 50 --json-errors
beztrace trace artwork/A.png --format svg --output review/A.svg \
  --source-box ink --target-y-min 0 --target-y-max 700 \
  --advance 600 --lsb 50 --json-errors
```

These dimensions are examples: supply your own baseline, height and spacing.
JSON retains font-style Y-up coordinates. Default SVG is already visually
upright; do not flip it again. See the [tracing workflow](../skills/beztrace-vectorize-image/references/workflow.md).

## Match a second master to a reference

In Codex, begin with `$beztrace-match-masters`; in Claude Code, begin with
`/beztrace-match-masters`. For example:

```text
Use Beztrace 0.2.2 to match artwork/Bold.png to Regular.outline.json at 1000 UPM.
Keep Regular bit-for-bit unchanged and allow no extra on-curves. Use its
on-curve and total-node counts as the ceilings, with a 1-unit fit tolerance.
Ask me for the image placement if it is not specified. Write a pair job,
run it into a new review directory, and show fidelity bounds, corresponding
nodes and intermediate weights. Report a refusal without relaxing the limits.
```

The agent prepares a job using the [pair workflow and schema](PAIR_WORKFLOW.md),
then runs:

```sh
beztrace match-pair JOB.json --output-directory NEW_REVIEW_DIRECTORY --json-errors
```

The output directory must be new. The first input is the reference; use
`referencePolicy: "fixed"` and `maxAdditionalOnCurveNodes: 0` to preserve it.
Images need an explicit affine placement; SVG files are not neutral outline JSON.
Two-image matching needs explicit on-curve and total-node budgets.

Review `comparison.json`, require a `recommendedRoute`, and open `index.html`
to inspect the pair and intermediate weights before consuming
`recommended.master-set.json`. Equal node counts alone do not establish
compatibility. Optional [joint smoothing](JOINT_SMOOTHING.md) retains the same
original-source error limit, reference and node structure; inspect its
`report.status`, including any refusal.

## Other agents and Glyphs

An agent with local shell and file access can use the CLI directly, or read the
two `SKILL.md` files and their supporting references. Provide the source files,
placement, tolerance, node budgets and a fresh output directory in your request.

For live Glyphs application, install the separately released
[companion 0.2.2/build 27](GLYPHS_COMPANION_RELEASE.md). Native scripted use also
needs an available, authorized Glyphs scripting connection. Standalone tracing
and matching prepare detached paths; they do not write a font file. Preview and
apply through the companion's supported interface, retaining its stale-target
and Undo checks. A coding-agent skill does not itself add a Glyphs MCP server.
