---
name: itb-rdf-validator-config-check
description: Validate and fix RDF validator config.properties against ITB SHACL validator documentation for this repository.
---

Use this skill when working on the validator domain config at resources/mobilitydcat-ap/config.properties.

Authoritative documentation sources:
- Topic: standalone_validators (via ITB MCP list_topics and get_documentation)
- RDF setup guide (step 3):
  https://www.itb.ec.europa.eu/docs-source/guides/validatingRDF/sections/guide__validatingRDF__steps__step3.rst
- RDF validator property reference:
  https://www.itb.ec.europa.eu/docs-source/guides/validatingRDF/sections/guide__validatingRDF__references__validator_props.rst

Critical rules to enforce:
1. FULL_TYPE semantics:
- FULL_TYPE equals TYPE.OPTION when options exist.
- FULL_TYPE equals TYPE when no options exist.

2. Keys that must use FULL_TYPE postfixes:
- validator.shaclFile.FULL_TYPE
- validator.shaclFile.FULL_TYPE.remote.N.url
- validator.shaclFile.FULL_TYPE.remote.N.type
- validator.externalShapes.FULL_TYPE
- Any other property documented with the FULL_TYPE placeholder.

3. Type and option consistency:
- validator.type lists all supported TYPE values.
- validator.typeOptions.TYPE lists all OPTION values for that TYPE.
- Any configured TYPE.OPTION usage in shaclFile or externalShapes must be declared by validator.typeOptions.TYPE.
- Do not use TYPE-only keys for FULL_TYPE-only properties when options exist.

4. Baseline syntax/channel constraints:
- validator.channels values limited to form, rest_api, soap_api.
- validator.contentSyntax should be valid RDF MIME types used by ITB RDF validator.

5. URL health:
- Every configured remote URL should resolve (2xx after redirects).

Required verification workflow:
1. Read resources/mobilitydcat-ap/config.properties.
2. Build TYPE, OPTION, and computed FULL_TYPE sets.
3. Check for invalid FULL_TYPE usage in:
- validator.shaclFile.<X>.remote.*
- validator.externalShapes.<X>
4. Check for orphaned TYPE.OPTION blocks not present in validator.typeOptions.
5. Extract all URLs and test them with GET and redirects.
6. Report findings and apply minimal edits.

Implementation note:
- Keep checks language- and shell-agnostic.
- Prefer repository/tooling-native checks or agent tools over embedded shell snippets.

Fix strategy for this repository:
- Keep v1.1.0 and v3.0.0 as optioned types.
- Keep cv as an option where cv-specific SHACL mappings exist.
- Use option-specific externalShapes entries:
  validator.externalShapes.v1.1.0.core/range/full/cv
  validator.externalShapes.v3.0.0.core/range/full/cv
- Avoid broad TYPE-only externalShapes keys for optioned types.
