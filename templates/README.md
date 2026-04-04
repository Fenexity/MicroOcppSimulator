# MicroOCPP Simulator Templates

This directory contains template files used to generate `mo_store`
configurations for multiple OCPP simulators.

## Template Structure

### `mo_store_v16_template/`

Base files for generated OCPP 1.6 simulators.

### `mo_store_v201_template/`

Base files for generated OCPP 2.0.1 simulators.

## Placeholders

The generator scripts replace these placeholders automatically:

- `{{CHARGER_ID}}`: unique charger ID, for example `charger-v16-001`
- `{{CSMS_URL}}`: WebSocket URL for the backend
- `{{AUTH_PASSWORD}}`: Basic Auth password for OCPP 2.0.1
- `{{CITRINEOS_IP}}`: detected IP address of the CitrineOS container

## Generation Flow

Do not edit these templates manually if they are generated from
`mo_store_v16/` or `mo_store_v201/`.

Typical flow:

1. Run `./generate-simulators.sh`.
2. The script copies the current `mo_store` files into template folders.
3. The script replaces concrete values with placeholders.
4. Generated simulators use those templates as their base configuration.
