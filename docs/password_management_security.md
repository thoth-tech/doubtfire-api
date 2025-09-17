# Password Management Security Documentation

## Overview

This document outlines the security measures implemented for the password management system in Doubtfire.

## Security Features

### Password Storage
- **Bcrypt Hashing**: All passwords are hashed using BCrypt with salt
- **No Plain Text Storage**: Passwords are never stored in plain text
- **Salt Generation**: Each password gets a unique salt automatically

### Password Validation
- **Minimum Length**: Passwords must be at least 8 characters long
- **Confirmation Matching**: Password confirmation must match the original password
- **Required Fields**: Password is required during registration and password changes

### Password Reset Security
- **Token Generation**: Reset tokens are generated using `SecureRandom.urlsafe_base64`
- **Token Expiration**: Reset tokens expire after 24 hours
- **Single Use**: Tokens are cleared after successful password reset
- **Email Privacy**: The system doesn't reveal whether an email exists in the system

### Authentication Security
- **Token-Based Auth**: Uses secure authentication tokens for API access
- **Token Expiration**: Authentication tokens have configurable expiration times
- **Current Password Verification**: Password changes require current password verification
- **Rate Limiting**: Consider implementing rate limiting for authentication attempts

## API Endpoints Security

### Registration Endpoint (`POST /api/register`)
- Validates all required fields
- Checks for existing username/email
- Validates password strength
- Creates user with student role by default
- Returns authentication token on success

### Password Reset Request (`POST /api/password/reset`)
- Accepts email address
- Generates secure reset token
- Logs reset request (in production, send email)
- Doesn't reveal if email exists

### Password Reset Confirmation (`POST /api/password/reset/confirm`)
- Validates reset token
- Checks token expiration
- Validates new password
- Clears reset token after successful reset

### Change Password (`POST /api/password/change`)
- Requires authentication
- Verifies current password
- Validates new password
- Updates password hash

## Security Considerations

### Environment-Specific Behavior
- Password management endpoints are only available when using database authentication
- LDAP, AAF, and SAML authentication methods bypass password management
- This ensures compatibility with existing institutional authentication systems

### Error Handling
- Generic error messages to prevent information disclosure
- Detailed validation errors only for legitimate users
- Proper HTTP status codes for different error conditions

### Logging
- All password-related actions are logged with IP addresses
- Failed authentication attempts are logged
- Password reset requests are logged with tokens (for development)

## Implementation Notes

### Database Schema
The following fields are used for password management:
- `encrypted_password`: Stores the bcrypt hash
- `reset_password_token`: Stores reset tokens
- `reset_password_sent_at`: Tracks when reset was requested

### Frontend Security
- Form validation on both client and server side
- Secure token handling in Angular services
- Proper error message display
- Password confirmation matching

## Recommendations for Production

### Email Integration
- Implement email sending for password reset links
- Use secure email templates
- Include expiration time in email
- Consider email rate limiting

### Rate Limiting
- Implement rate limiting for authentication attempts
- Limit password reset requests per IP/email
- Implement account lockout after failed attempts

### Monitoring
- Monitor for suspicious authentication patterns
- Log and alert on multiple failed attempts
- Track password reset request patterns

### Additional Security
- Consider implementing password strength requirements
- Add CAPTCHA for registration and password reset
- Implement session management improvements
- Consider two-factor authentication for sensitive accounts

## Testing

Comprehensive tests have been implemented covering:
- User registration with valid/invalid data
- Password reset token generation and validation
- Password change with authentication
- Error handling and edge cases
- Security boundary conditions

Run tests with:
```bash
rails test test/api/password_management_test.rb
```

## Configuration

### Environment Variables
- `DF_AUTH_METHOD`: Set to 'database' to enable password management
- Other authentication methods (ldap, aaf, saml) will disable password management endpoints

### Database Migrations
Ensure the following migrations are applied:
- Devise user creation migration
- Password reset token fields migration
- Any additional user fields migration

