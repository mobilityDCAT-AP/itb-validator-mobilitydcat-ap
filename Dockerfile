# Use the ITB SHACL Validator base image
FROM isaitb/shacl-validator:latest

LABEL org.opencontainers.image.source=https://github.com/mobilityDCAT-AP/itb-validator-mobilitydcat-ap

# Copy the configuration resources into the container
# The validator will auto-discover domains from subfolders containing config.properties
COPY resources /validator/resources/

# Set the root directory for validator resources (REQUIRED)
ENV validator.resourceRoot=/validator/resources/

# Expose the default validator port
EXPOSE 8080

# Health check to ensure the validator is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/shacl/mobilityDCAT-AP/api/info || exit 1
