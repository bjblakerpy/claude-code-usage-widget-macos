# Notion to GitHub Code Generation Agent

An automated agent that reads code specifications from Notion, uses Claude AI to generate code, and pushes the results to GitHub.

## Features

- 📖 **Read from Notion**: Automatically fetches and parses Notion pages
- 🤖 **AI Code Generation**: Uses Claude Sonnet 4 to generate production-ready code
- 📦 **GitHub Integration**: Creates repositories and commits code automatically
- 🔄 **Complete Workflow**: End-to-end automation from spec to deployed code

## Prerequisites

You'll need API keys/tokens for:

1. **Notion Integration** - [Create one here](https://www.notion.so/my-integrations)
2. **Anthropic API Key** - [Get it here](https://console.anthropic.com/)
3. **GitHub Personal Access Token** - [Create one here](https://github.com/settings/tokens)

## Setup

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Set Up Notion Integration

1. Go to [Notion Integrations](https://www.notion.so/my-integrations)
2. Click "New integration"
3. Give it a name (e.g., "Code Gen Agent")
4. Copy the "Internal Integration Token"
5. Go to your Notion page with code specs
6. Click the "..." menu → "Connections" → Add your integration

### 3. Set Up GitHub Token

1. Go to [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)
2. Click "Generate new token (classic)"
3. Give it a name and select scopes:
   - `repo` (full control of private repositories)
   - `workflow` (if you want to update GitHub Actions)
4. Copy the token

### 4. Configure Environment Variables

Create a `.env` file in the project directory:

```bash
# Notion
NOTION_TOKEN=secret_xxxxxxxxxxxxx

# Anthropic
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxx

# GitHub
GITHUB_TOKEN=ghp_xxxxxxxxxxxxx
GITHUB_USERNAME=your-github-username

# Optional: Default Notion page to process
NOTION_PAGE_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 5. Get Your Notion Page ID

The page ID is the part of the URL after your workspace name and before the question mark:

```
https://www.notion.so/My-Code-Spec-abc123def456?pvs=4
                                  ^^^^^^^^^^^^
                                  This is your page ID
```

## Usage

### Basic Usage

```python
from notion_to_github_agent import NotionToGitHubAgent

agent = NotionToGitHubAgent(
    notion_token="your-notion-token",
    anthropic_api_key="your-anthropic-key",
    github_token="your-github-token",
    github_username="your-username"
)

# Process a Notion page and push to GitHub
result = agent.process_notion_spec(
    notion_page_id="your-page-id",
    repo_name="my-generated-project",
    file_path="src/main.py"
)

print(f"Code pushed to: {result['repo_url']}")
```

### Run from Command Line

```bash
# Make sure environment variables are set
python notion_to_github_agent.py
```

### Advanced Usage

```python
# Custom instructions for Claude
result = agent.process_notion_spec(
    notion_page_id="abc123",
    repo_name="my-api-server",
    file_path="server.py",
    additional_instructions="""
    - Use FastAPI framework
    - Include input validation with Pydantic
    - Add comprehensive error handling
    - Include unit tests
    - Use async/await patterns
    """
)

# Process multiple files
specs = [
    ("page-id-1", "backend.py", "Backend API"),
    ("page-id-2", "frontend.js", "React frontend"),
    ("page-id-3", "database.sql", "Database schema"),
]

for page_id, file_path, description in specs:
    agent.process_notion_spec(
        notion_page_id=page_id,
        repo_name="my-full-stack-app",
        file_path=file_path,
        additional_instructions=description
    )
```

## Workflow Example

1. **Write your spec in Notion**:
   ```
   # User Authentication API

   Create a REST API for user authentication with the following endpoints:

   - POST /register - Create new user account
   - POST /login - Authenticate and return JWT token
   - GET /profile - Get current user profile (requires auth)
   - PUT /profile - Update user profile (requires auth)

   Requirements:
   - Use JWT for authentication
   - Hash passwords with bcrypt
   - Validate email format
   - Return appropriate HTTP status codes
   ```

2. **Run the agent**:
   ```bash
   export NOTION_PAGE_ID=your-page-id
   python notion_to_github_agent.py
   ```

3. **Check GitHub**: Your code will be automatically committed to a new repository!

## Notion Page Structure Tips

For best results, structure your Notion pages like this:

```
# Project Title

## Overview
Brief description of what needs to be built

## Requirements
- Feature 1
- Feature 2
- Feature 3

## Technical Details
- Language: Python 3.10+
- Framework: FastAPI
- Database: PostgreSQL

## API Endpoints
Detailed endpoint specifications...

## Code Examples
```python
# Any example code or patterns to follow
```
```

## Customization

### Change the AI Model

Edit the `generate_code_with_claude` method:

```python
data = {
    "model": "claude-opus-4-20250514",  # Use Opus for more complex tasks
    "max_tokens": 8000,  # Increase for longer code
    ...
}
```

### Add Multiple Files

Create a wrapper function:

```python
def generate_project(notion_page_id, repo_name):
    # Generate main code
    main_result = agent.process_notion_spec(
        notion_page_id, repo_name, "main.py"
    )
    
    # Generate tests
    agent.process_notion_spec(
        notion_page_id, repo_name, "test_main.py",
        additional_instructions="Generate comprehensive unit tests"
    )
    
    # Generate README
    agent.process_notion_spec(
        notion_page_id, repo_name, "README.md",
        additional_instructions="Generate a comprehensive README"
    )
```

### Add Error Notifications

```python
import smtplib
from email.message import EmailMessage

try:
    result = agent.process_notion_spec(notion_page_id)
except Exception as e:
    # Send error notification
    msg = EmailMessage()
    msg['Subject'] = 'Code Generation Failed'
    msg['To'] = 'you@email.com'
    msg.set_content(f'Error: {str(e)}')
    # Send email...
```

## Scheduling

### Run on a Schedule with Cron

```bash
# Run every day at 9 AM
0 9 * * * cd /path/to/project && /usr/bin/python3 notion_to_github_agent.py
```

### Run with GitHub Actions

Create `.github/workflows/generate-code.yml`:

```yaml
name: Generate Code from Notion

on:
  schedule:
    - cron: '0 9 * * *'  # Daily at 9 AM
  workflow_dispatch:  # Manual trigger

jobs:
  generate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - name: Install dependencies
        run: pip install -r requirements.txt
      - name: Run agent
        env:
          NOTION_TOKEN: ${{ secrets.NOTION_TOKEN }}
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GH_TOKEN }}
          GITHUB_USERNAME: ${{ github.actor }}
          NOTION_PAGE_ID: ${{ secrets.NOTION_PAGE_ID }}
        run: python notion_to_github_agent.py
```

## Troubleshooting

### "Page not found" error
- Make sure you've shared the Notion page with your integration
- Double-check the page ID in the URL

### "Repository creation failed"
- Verify your GitHub token has `repo` scope
- Check that the repository name is valid (lowercase, hyphens only)

### "Invalid API key"
- Ensure your Anthropic API key starts with `sk-ant-`
- Check that you have sufficient credits

### Code quality issues
- Provide more detailed specifications in Notion
- Add examples of desired code style
- Use the `additional_instructions` parameter

## Security Notes

⚠️ **Never commit your `.env` file or API keys to version control!**

Add to `.gitignore`:
```
.env
*.env
.env.*
```

## License

MIT License - feel free to use and modify as needed!

## Contributing

Suggestions and improvements welcome! This is a starting point that you can customize for your specific workflow.
