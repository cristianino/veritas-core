//// Contrato de votaciones sobre Cardano (Plutus V3, modelo eUTXO).
////
//// Modelo "token de voto" sin contencion:
////   - La AUTORIDAD acuna un token de votante por cada persona elegible (Issue).
////   - Para votar, el votante QUEMA su token y crea su propia papeleta (Cast):
////     un UTXO en la direccion del script cuyo datum guarda el candidato elegido.
////   - Como cada voto es su propio UTXO, no compiten entre si (no hay contencion).
////   - Al cerrar (Close), la autoridad puede recuperar las papeletas tras la fecha limite.
////
//// El conteo final se hace off-chain leyendo todas las papeletas del script.

use aiken/collection/list
use aiken/interval
use cardano/address.{Script}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction}

/// Nombre del activo que representa el derecho a votar (1 token = 1 voto).
const voter_asset: ByteArray = "VOTER"

/// Datum que se guarda en cada papeleta: el indice del candidato elegido.
pub type BallotDatum {
  candidate: Int,
}

/// Acciones posibles al mintear/quemar bajo esta politica.
pub type MintAction {
  /// La autoridad emite tokens de votante para los elegibles.
  Issue
  /// Un votante quema su token y registra su voto por `candidate`.
  Cast { candidate: Int }
}

/// Acciones posibles al gastar una papeleta.
pub type SpendAction {
  /// La autoridad recupera las papeletas una vez cerrada la votacion.
  Close
}

/// Verifica si un output es una papeleta valida por `candidate` en este script.
fn is_valid_ballot(output: Output, script: PolicyId, candidate: Int) -> Bool {
  when output.address.payment_credential is {
    Script(hash) ->
      if hash == script {
        when output.datum is {
          InlineDatum(data) -> {
            expect ballot: BallotDatum = data
            ballot.candidate == candidate
          }
          _ -> False
        }
      } else {
        False
      }
    _ -> False
  }
}

/// Validator parametrizado en tiempo de compilacion por:
///   - `authority`: quien organiza la eleccion (emite tokens y cierra).
///   - `deadline`: instante limite (POSIX ms); despues no se puede votar.
///   - `candidate_count`: cantidad de candidatos; los votos validos van de 0 a n-1.
validator voting(authority: ByteArray, deadline: Int, candidate_count: Int) {
  mint(redeemer: MintAction, policy_id: PolicyId, self: Transaction) {
    let voting_open = interval.is_entirely_before(self.validity_range, deadline)

    when redeemer is {
      // Solo la autoridad emite tokens, con la votacion abierta,
      // y debe crear al menos un token de votante.
      Issue -> {
        let signed_by_authority = list.has(self.extra_signatories, authority)
        let mints_voter_tokens = quantity_of(self.mint, policy_id, voter_asset) > 0
        voting_open && signed_by_authority && mints_voter_tokens
      }

      // Votar: quemar exactamente 1 token, candidato valido, votacion abierta,
      // y producir exactamente una papeleta correcta en el propio script.
      Cast { candidate } -> {
        let burns_one_token = quantity_of(self.mint, policy_id, voter_asset) == -1
        let valid_candidate = candidate >= 0 && candidate < candidate_count
        let ballots = list.count(
          self.outputs,
          fn(output) { is_valid_ballot(output, policy_id, candidate) },
        )
        voting_open && burns_one_token && valid_candidate && ballots == 1
      }
    }
  }

  spend(
    _datum: Option<BallotDatum>,
    redeemer: SpendAction,
    _own_ref: OutputReference,
    self: Transaction,
  ) {
    when redeemer is {
      // La autoridad recupera las papeletas solo despues de la fecha limite.
      Close -> {
        let signed_by_authority = list.has(self.extra_signatories, authority)
        let voting_closed = interval.is_entirely_after(
          self.validity_range,
          deadline,
        )
        signed_by_authority && voting_closed
      }
    }
  }

  else(_) {
    fail
  }
}

// ===========================================================================
// Pruebas
// ===========================================================================

const test_policy: PolicyId =
  #"00000000000000000000000000000000000000000000000000000000"

const test_authority: ByteArray =
  #"11111111111111111111111111111111111111111111111111111111"

const test_deadline: Int = 1000

const test_candidates: Int = 3

/// Construye una papeleta (UTXO en el script) que vota por `candidate`.
fn ballot_output(candidate: Int) -> Output {
  let datum: Data = BallotDatum { candidate }
  Output {
    address: address.from_script(test_policy),
    value: assets.from_lovelace(2_000_000),
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

test cast_valid_vote() {
  let tx = Transaction {
    ..transaction.placeholder,
    mint: assets.from_asset(test_policy, voter_asset, -1),
    outputs: [ballot_output(1)],
    validity_range: interval.entirely_before(test_deadline),
  }
  voting.mint(
    test_authority,
    test_deadline,
    test_candidates,
    Cast { candidate: 1 },
    test_policy,
    tx,
  )
}

test cast_rejects_invalid_candidate() {
  let tx = Transaction {
    ..transaction.placeholder,
    mint: assets.from_asset(test_policy, voter_asset, -1),
    outputs: [ballot_output(9)],
    validity_range: interval.entirely_before(test_deadline),
  }
  !voting.mint(
    test_authority,
    test_deadline,
    test_candidates,
    Cast { candidate: 9 },
    test_policy,
    tx,
  )
}

test cast_rejects_without_burning_token() {
  let tx = Transaction {
    ..transaction.placeholder,
    mint: assets.zero,
    outputs: [ballot_output(1)],
    validity_range: interval.entirely_before(test_deadline),
  }
  !voting.mint(
    test_authority,
    test_deadline,
    test_candidates,
    Cast { candidate: 1 },
    test_policy,
    tx,
  )
}

test cast_rejects_datum_candidate_mismatch() {
  // El votante dice votar por 1 pero la papeleta guarda 2: debe fallar.
  let tx = Transaction {
    ..transaction.placeholder,
    mint: assets.from_asset(test_policy, voter_asset, -1),
    outputs: [ballot_output(2)],
    validity_range: interval.entirely_before(test_deadline),
  }
  !voting.mint(
    test_authority,
    test_deadline,
    test_candidates,
    Cast { candidate: 1 },
    test_policy,
    tx,
  )
}

test cast_rejects_after_deadline() {
  let tx = Transaction {
    ..transaction.placeholder,
    mint: assets.from_asset(test_policy, voter_asset, -1),
    outputs: [ballot_output(1)],
    validity_range: interval.entirely_after(test_deadline),
  }
  !voting.mint(
    test_authority,
    test_deadline,
    test_candidates,
    Cast { candidate: 1 },
    test_policy,
    tx,
  )
}

test issue_requires_authority_signature() {
  let tx = Transaction {
    ..transaction.placeholder,
    mint: assets.from_asset(test_policy, voter_asset, 5),
    extra_signatories: [test_authority],
    validity_range: interval.entirely_before(test_deadline),
  }
  voting.mint(
    test_authority,
    test_deadline,
    test_candidates,
    Issue,
    test_policy,
    tx,
  )
}

test issue_rejects_unauthorized() {
  // Nadie firmo como autoridad: la emision debe fallar.
  let tx = Transaction {
    ..transaction.placeholder,
    mint: assets.from_asset(test_policy, voter_asset, 5),
    extra_signatories: [],
    validity_range: interval.entirely_before(test_deadline),
  }
  !voting.mint(
    test_authority,
    test_deadline,
    test_candidates,
    Issue,
    test_policy,
    tx,
  )
}
