# Creating a TypeScript MCP Server for Authentication

This guide covers building a Model Context Protocol (MCP) server in TypeScript that handles user authentication for a remote web server.

## Prerequisites

- Node.js 18+ and npm/yarn
- TypeScript knowledge
- Basic understanding of authentication flows

## Project Setup

### 1. Initialize Project

```bash
mkdir auth-mcp-server
cd auth-mcp-server
npm init -y
npm install @modelcontextprotocol/sdk zod
npm install -D typescript @types/node ts-node
```

### 2. TypeScript Configuration

Create `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

## Core Implementation

### 3. Main Server File

Create `src/index.ts`:

```typescript
#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
  CallToolResult,
  TextContent,
  ImageContent,
  EmbeddedResource
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";

// Authentication schemas
const LoginSchema = z.object({
  username: z.string().min(1, "Username is required"),
  password: z.string().min(1, "Password is required"),
  remoteHost: z.string().url("Valid URL required")
});

const ValidateTokenSchema = z.object({
  token: z.string().min(1, "Token is required"),
  remoteHost: z.string().url("Valid URL required")
});

const LogoutSchema = z.object({
  token: z.string().min(1, "Token is required"),
  remoteHost: z.string().url("Valid URL required")
});

const RefreshTokenSchema = z.object({
  refreshToken: z.string().min(1, "Refresh token is required"),
  remoteHost: z.string().url("Valid URL required")
});

// Authentication response types
interface AuthResponse {
  success: boolean;
  token?: string;
  refreshToken?: string;
  expiresIn?: number;
  user?: {
    id: string;
    username: string;
    email?: string;
    roles?: string[];
  };
  error?: string;
}

class AuthMCPServer {
  private server: Server;

  constructor() {
    this.server = new Server(
      {
        name: "auth-mcp-server",
        version: "1.0.0",
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.setupToolHandlers();
    this.setupErrorHandling();
  }

  private setupErrorHandling(): void {
    this.server.onerror = (error) => {
      console.error("[MCP Error]", error);
    };

    process.on("SIGINT", async () => {
      await this.server.close();
      process.exit(0);
    });
  }

  private setupToolHandlers(): void {
    // List available tools
    this.server.setRequestHandler(ListToolsRequestSchema, async () => {
      return {
        tools: [
          {
            name: "auth_login",
            description: "Authenticate user with username and password",
            inputSchema: {
              type: "object",
              properties: {
                username: {
                  type: "string",
                  description: "User's username"
                },
                password: {
                  type: "string",
                  description: "User's password"
                },
                remoteHost: {
                  type: "string",
                  description: "Remote server URL (e.g., https://api.example.com)"
                }
              },
              required: ["username", "password", "remoteHost"]
            }
          },
          {
            name: "auth_validate_token",
            description: "Validate an authentication token",
            inputSchema: {
              type: "object",
              properties: {
                token: {
                  type: "string",
                  description: "JWT or session token to validate"
                },
                remoteHost: {
                  type: "string",
                  description: "Remote server URL"
                }
              },
              required: ["token", "remoteHost"]
            }
          },
          {
            name: "auth_refresh_token",
            description: "Refresh an expired authentication token",
            inputSchema: {
              type: "object",
              properties: {
                refreshToken: {
                  type: "string",
                  description: "Refresh token to exchange for new access token"
                },
                remoteHost: {
                  type: "string",
                  description: "Remote server URL"
                }
              },
              required: ["refreshToken", "remoteHost"]
            }
          },
          {
            name: "auth_logout",
            description: "Logout user and invalidate token",
            inputSchema: {
              type: "object",
              properties: {
                token: {
                  type: "string",
                  description: "Authentication token to invalidate"
                },
                remoteHost: {
                  type: "string",
                  description: "Remote server URL"
                }
              },
              required: ["token", "remoteHost"]
            }
          },
          {
            name: "auth_get_user_info",
            description: "Get user information from valid token",
            inputSchema: {
              type: "object",
              properties: {
                token: {
                  type: "string",
                  description: "Valid authentication token"
                },
                remoteHost: {
                  type: "string",
                  description: "Remote server URL"
                }
              },
              required: ["token", "remoteHost"]
            }
          }
        ] as Tool[]
      };
    });

    // Handle tool calls
    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const { name, arguments: args } = request.params;

      try {
        switch (name) {
          case "auth_login":
            return await this.handleLogin(args);
          case "auth_validate_token":
            return await this.handleValidateToken(args);
          case "auth_refresh_token":
            return await this.handleRefreshToken(args);
          case "auth_logout":
            return await this.handleLogout(args);
          case "auth_get_user_info":
            return await this.handleGetUserInfo(args);
          default:
            throw new Error(`Unknown tool: ${name}`);
        }
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : "Unknown error";
        return {
          content: [
            {
              type: "text",
              text: `Error: ${errorMessage}`
            } as TextContent
          ]
        };
      }
    });
  }

  private async handleLogin(args: unknown): Promise<CallToolResult> {
    const { username, password, remoteHost } = LoginSchema.parse(args);

    try {
      const response = await fetch(`${remoteHost}/auth/login`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ username, password })
      });

      const data: AuthResponse = await response.json();

      if (data.success && data.token) {
        return {
          content: [
            {
              type: "text",
              text: `Login successful!\nToken: ${data.token}\nExpires in: ${data.expiresIn || 'Unknown'} seconds\nUser: ${data.user?.username || username}`
            } as TextContent
          ]
        };
      } else {
        return {
          content: [
            {
              type: "text",
              text: `Login failed: ${data.error || 'Invalid credentials'}`
            } as TextContent
          ]
        };
      }
    } catch (error) {
      throw new Error(`Login request failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  }

  private async handleValidateToken(args: unknown): Promise<CallToolResult> {
    const { token, remoteHost } = ValidateTokenSchema.parse(args);

    try {
      const response = await fetch(`${remoteHost}/auth/validate`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token}`
        }
      });

      const data: AuthResponse = await response.json();

      return {
        content: [
          {
            type: "text",
            text: data.success 
              ? `Token is valid\nUser: ${data.user?.username || 'Unknown'}`
              : `Token validation failed: ${data.error || 'Invalid token'}`
          } as TextContent
        ]
      };
    } catch (error) {
      throw new Error(`Token validation failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  }

  private async handleRefreshToken(args: unknown): Promise<CallToolResult> {
    const { refreshToken, remoteHost } = RefreshTokenSchema.parse(args);

    try {
      const response = await fetch(`${remoteHost}/auth/refresh`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ refreshToken })
      });

      const data: AuthResponse = await response.json();

      if (data.success && data.token) {
        return {
          content: [
            {
              type: "text",
              text: `Token refreshed successfully!\nNew Token: ${data.token}\nExpires in: ${data.expiresIn || 'Unknown'} seconds`
            } as TextContent
          ]
        };
      } else {
        return {
          content: [
            {
              type: "text",
              text: `Token refresh failed: ${data.error || 'Invalid refresh token'}`
            } as TextContent
          ]
        };
      }
    } catch (error) {
      throw new Error(`Token refresh failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  }

  private async handleLogout(args: unknown): Promise<CallToolResult> {
    const { token, remoteHost } = LogoutSchema.parse(args);

    try {
      const response = await fetch(`${remoteHost}/auth/logout`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token}`
        }
      });

      const data: AuthResponse = await response.json();

      return {
        content: [
          {
            type: "text",
            text: data.success 
              ? "Logout successful"
              : `Logout failed: ${data.error || 'Unknown error'}`
          } as TextContent
        ]
      };
    } catch (error) {
      throw new Error(`Logout failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  }

  private async handleGetUserInfo(args: unknown): Promise<CallToolResult> {
    const { token, remoteHost } = ValidateTokenSchema.parse(args);

    try {
      const response = await fetch(`${remoteHost}/auth/user`, {
        method: "GET",
        headers: {
          "Authorization": `Bearer ${token}`
        }
      });

      const data: AuthResponse = await response.json();

      if (data.success && data.user) {
        const userInfo = [
          `User ID: ${data.user.id}`,
          `Username: ${data.user.username}`,
          data.user.email ? `Email: ${data.user.email}` : null,
          data.user.roles ? `Roles: ${data.user.roles.join(', ')}` : null
        ].filter(Boolean).join('\n');

        return {
          content: [
            {
              type: "text",
              text: userInfo
            } as TextContent
          ]
        };
      } else {
        return {
          content: [
            {
              type: "text",
              text: `Failed to get user info: ${data.error || 'Invalid token'}`
            } as TextContent
          ]
        };
      }
    } catch (error) {
      throw new Error(`Get user info failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  }

  async run(): Promise<void> {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error("Auth MCP server running on stdio");
  }
}

// Start the server
const server = new AuthMCPServer();
server.run().catch(console.error);
```

## Remote Server API Contract

Your remote web server should implement these endpoints:

### POST /auth/login
```typescript
// Request
{
  "username": "string",
  "password": "string"
}

// Response
{
  "success": boolean,
  "token"?: "string",
  "refreshToken"?: "string", 
  "expiresIn"?: number,
  "user"?: {
    "id": "string",
    "username": "string",
    "email"?: "string",
    "roles"?: string[]
  },
  "error"?: "string"
}
```

### POST /auth/validate
```typescript
// Headers: Authorization: Bearer <token>
// Response: Same as login
```

### POST /auth/refresh
```typescript
// Request
{
  "refreshToken": "string"
}
// Response: Same as login
```

### POST /auth/logout
```typescript
// Headers: Authorization: Bearer <token>
// Response: { "success": boolean, "error"?: "string" }
```

### GET /auth/user
```typescript
// Headers: Authorization: Bearer <token>
// Response: Same as login (user info focus)
```

## Build and Package

### 4. Package Configuration

Update `package.json`:

```json
{
  "name": "auth-mcp-server",
  "version": "1.0.0",
  "main": "dist/index.js",
  "bin": {
    "auth-mcp-server": "./dist/index.js"
  },
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "ts-node src/index.ts"
  }
}
```

### 5. Build and Test

```bash
npm run build
chmod +x dist/index.js
```

## Claude Code Configuration

Add to Claude Code settings (`~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "auth-server": {
      "command": "node",
      "args": ["/path/to/auth-mcp-server/dist/index.js"]
    }
  }
}
```

## Usage Examples

Once configured, Claude can use these tools:

```typescript
// Login user
await callTool("auth_login", {
  username: "john_doe",
  password: "secure_password",
  remoteHost: "https://api.myapp.com"
});

// Validate token
await callTool("auth_validate_token", {
  token: "jwt_token_here",
  remoteHost: "https://api.myapp.com"
});

// Get user info
await callTool("auth_get_user_info", {
  token: "jwt_token_here", 
  remoteHost: "https://api.myapp.com"
});
```

## Security Considerations

- Never log sensitive data (passwords, tokens)
- Use HTTPS for all remote communications
- Implement rate limiting on the remote server
- Validate all inputs with Zod schemas
- Consider token encryption for storage
- Implement proper error handling without exposing internals

## Extensions

Consider adding:
- Multi-factor authentication support
- OAuth2/OIDC flows
- Session management
- Password reset flows
- User registration
- Role-based access control

This MCP server provides a complete authentication interface that Claude can use to handle user authentication with any compatible remote web server.