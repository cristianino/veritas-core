//! Off-chain (paso 1): deriva la identidad on-chain del contrato de votaciones.
//!
//! Toma el blueprint `plutus.json` generado por Aiken, le aplica los parametros
//! del validator (authority, deadline, candidate_count) y calcula:
//!   - el Policy ID (= hash del script ya parametrizado)
//!   - la direccion del script en testnet
//!
//! Estos valores DEBEN coincidir con los que produce `aiken blueprint policy`
//! y `aiken blueprint address`, lo que valida todo el pipeline en Rust.

use pallas_addresses::{Network, ShelleyAddress, ShelleyDelegationPart, ShelleyPaymentPart};
use pallas_crypto::hash::Hasher;
use serde_json::Value;
use std::fs;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 1. Cargar el blueprint y extraer el codigo compilado (parametrizado).
    let blueprint: Value = serde_json::from_str(&fs::read_to_string("../plutus.json")?)?;
    let compiled_hex = blueprint["validators"][0]["compiledCode"]
        .as_str()
        .ok_or("no se encontro compiledCode en el blueprint")?;
    let script_bytes = hex::decode(compiled_hex)?;

    // 2. Construir la lista de parametros como PlutusData (CBOR).
    //    Es la lista [ authority, deadline, candidate_count ]:
    //      - authority: bytestring de 28 bytes (aqui 0x01 repetido)
    //      - deadline: 1000
    //      - candidate_count: 3
    //    CBOR: 0x83 (array de 3) | 0x58 0x1c <28 bytes> | 0x19 0x03e8 | 0x03
    let authority = [0x01u8; 28];
    let mut params_cbor = vec![0x83u8]; // array definido de 3 elementos
    params_cbor.extend_from_slice(&[0x58, 0x1c]); // bytestring de 28 bytes
    params_cbor.extend_from_slice(&authority);
    params_cbor.extend_from_slice(&[0x19, 0x03, 0xe8]); // entero 1000
    params_cbor.push(0x03); // entero 3

    // 3. Aplicar los parametros al script.
    let applied = uplc::tx::apply_params_to_script(&params_cbor, &script_bytes)
        .map_err(|e| format!("apply_params_to_script: {e:?}"))?;

    // 4. Calcular el hash del script. En Plutus V3 el hash es
    //    blake2b-224( 0x03 || script_bytes ).
    let mut hasher = Hasher::<224>::new();
    hasher.input(&[0x03]);
    hasher.input(&applied);
    let policy_id = hasher.finalize();

    // 5. Direccion de testnet: parte de pago = script, sin delegacion.
    let address = ShelleyAddress::new(
        Network::Testnet,
        ShelleyPaymentPart::Script(policy_id),
        ShelleyDelegationPart::Null,
    );

    println!("Policy ID : {}", hex::encode(policy_id));
    println!("Address   : {}", address.to_bech32()?);
    Ok(())
}
