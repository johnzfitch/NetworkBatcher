# Contributing to NetworkBatcher

Thank you for your interest in contributing to NetworkBatcher! This document provides guidelines and information for contributors.

## Getting Started

### Prerequisites

- Xcode 15.0 or later
- Swift 5.9 or later
- iOS 15.0+ deployment target

### Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/NetworkBatcher.git
   cd NetworkBatcher
   ```
3. Open Package.swift in Xcode or your preferred IDE

### Building

```bash
# Build the package
swift build

# Run tests
swift test

# Open in Xcode
open Package.swift
```

## Development Guidelines

### Code Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Keep functions focused and concise
- Add documentation comments for public APIs

### Commit Messages

Use clear, descriptive commit messages:

```
feat: Add request compression support
fix: Handle network timeout correctly
docs: Update README with new API
test: Add tests for BatcherConfiguration
refactor: Simplify priority classification logic
```

Prefixes:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `test:` Test additions/changes
- `refactor:` Code refactoring
- `chore:` Maintenance tasks

### Pull Requests

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes with appropriate tests

3. Run tests and ensure they pass:
   ```bash
   swift test
   ```

4. Push to your fork and create a pull request

5. Fill out the PR template with:
   - Description of changes
   - Related issues
   - Testing performed
   - Screenshots (if UI changes)

### Testing

- Add unit tests for new functionality
- Ensure existing tests continue to pass
- Test on both simulator and physical device when possible
- Test different network conditions (WiFi, cellular, offline)

### Documentation

- Update README.md for user-facing changes
- Add inline documentation for public APIs
- Update CHANGELOG.md for notable changes

## Areas for Contribution

### High Priority

- [ ] Request compression (gzip/deflate)
- [ ] HTTP/2 multiplexing for same-host batches
- [ ] Request deduplication
- [ ] More analytics SDK wrappers
- [ ] Instruments integration for energy metrics

### Good First Issues

- Add more deferrable domains to default list
- Improve error messages
- Add more unit tests
- Documentation improvements

### Ideas Welcome

- Performance optimizations
- New configuration options
- Better debugging tools
- Integration examples

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Focus on constructive feedback
- Keep discussions on-topic

## Questions?

- Open an issue for bugs or feature requests
- Start a discussion for questions or ideas
- Tag issues appropriately (`bug`, `enhancement`, `question`, etc.)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for helping make NetworkBatcher better! 🎉
