# claude-agent-sdk: simple dict schemas make ALL fields required

**Tags:** claude-agent-sdk, mcp, tools, schema
**Related:** [plugin-system.md]

The `@tool` decorator's simple dict format (`{"name": str}`) converts ALL keys
to required fields in JSON Schema. There is no way to mark a field optional.

To make fields optional, use JSON Schema passthrough format:

    {
        "type": "object",
        "properties": {
            "required_field": {"type": "string"},
            "optional_field": {"type": "string"},
        },
        "required": ["required_field"],
    }

The SDK checks for `"type"` + `"properties"` keys and passes the dict through
as-is instead of converting it.

[plugin-system.md]: plugin-system.md
