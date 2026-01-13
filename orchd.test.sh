!#/sbin/bash
cat << 'EOF' | ./orchd
{
  "prompt": "Explain what this Go program does, briefly.",
  "code": "package main\n\nimport \"fmt\"\n\nfunc main() { fmt.Println(\"hello\") }\n",
  "models": [
    {
      "name": "gpt4",
      "provider": "openai",
      "model": "gpt-4.1",
      "api_key": "'"$OPENAI_API_KEY"'",
      "temperature": 0.2,
      "max_tokens": 256
    },
    {
      "name": "sonnet",
      "provider": "anthropic",
      "model": "claude-3.5-sonnet",
      "api_key": "'"$ANTHROPIC_API_KEY"'",
      "temperature": 0.2,
      "max_tokens": 256
    }
  ],
  "timeout_seconds": 30,
  "stream": true
}
EOF
