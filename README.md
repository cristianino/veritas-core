# VeritasCore

Contrato de **votaciones sobre Cardano** (Plutus V3) con su capa off-chain en Rust.
Es un port a Cardano de una vieja dApp de votaciones en Ethereum/Solidity, hecho como
ejercicio para entender Cardano a bajo nivel — **sin Haskell**: on-chain en
[Aiken](https://aiken-lang.org), off-chain en Rust con [`pallas`](https://github.com/txpipe/pallas)
y [`uplc`](https://crates.io/crates/uplc).

## Modelo: token de voto (1 token = 1 voto)

A diferencia de Ethereum (estado mutable global: `mapping(candidato => votos)`), en Cardano
el estado vive en UTXOs y el validator solo **verifica transiciones**. Por eso el diseño usa
tokens en lugar de un contador central:

1. **Emisión (`Issue`)** — la autoridad acuña un token de votante por cada persona elegible.
2. **Voto (`Cast { candidate }`)** — el votante **quema** su token y crea su propia **papeleta**:
   un UTXO en la dirección del script cuyo `datum` guarda el candidato elegido. Como cada voto
   es un UTXO independiente, **no hay contención** (miles de votos pueden entrar en el mismo bloque).
3. **Cierre (`Close`)** — pasada la fecha límite, la autoridad recupera las papeletas.

El conteo final se hace off-chain, recorriendo todas las papeletas del script y sumando por candidato.

> Nota: el contrato garantiza "1 token = 1 voto", pero la unicidad por persona depende de cómo la
> autoridad reparta los tokens off-chain (en cadena solo se hace cumplir la mecánica del token).

## Estructura

```
validators/voting.ak   Validator on-chain (mint: Issue/Cast, spend: Close) + pruebas
plutus.json            Blueprint CIP-57 generado por `aiken build`
offchain/              Capa off-chain en Rust (pallas + uplc)
  src/main.rs          Paso 1: aplica parámetros y deriva policy id + dirección
```

## On-chain (Aiken)

```sh
aiken check    # type-check + pruebas unitarias
aiken build    # genera plutus.json
```

El validator está parametrizado por `authority` (clave de la autoridad), `deadline` (POSIX ms)
y `candidate_count`. Aplicar parámetros produce el policy id y la dirección definitivos:

```sh
aiken blueprint policy   -m voting -v voting
aiken blueprint address  -m voting -v voting
```

## Off-chain (Rust)

Requisitos en Windows: toolchain **GNU** de Rust y un **gcc** (para `secp256k1-sys`).

```sh
rustup default stable-x86_64-pc-windows-gnu
# gcc de mingw-w64, p.ej. WinLibs (winget install BrechtSanders.WinLibs.POSIX.MSVCRT)
```

Compilar y ejecutar (desde PowerShell en Windows, para un PATH limpio):

```sh
cd offchain
cargo run
```

El paso 1 carga `plutus.json`, aplica los parámetros del validator y deriva el **policy id** y la
**dirección de testnet**, valores que coinciden con los de `aiken blueprint policy`/`address`.

## Estado

- [x] Validator on-chain — compila, 7/7 pruebas, blueprint generado.
- [x] Off-chain paso 1 — deriva la identidad on-chain (policy id + dirección), verificada.
- [ ] Transacciones off-chain: emitir tokens, votar, cerrar/contar.

## Licencia

Apache-2.0
