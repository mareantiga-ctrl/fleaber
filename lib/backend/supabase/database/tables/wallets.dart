import '../database.dart';

class WalletsTable extends SupabaseTable<WalletsRow> {
  @override
  String get tableName => 'wallets';

  @override
  WalletsRow createRow(Map<String, dynamic> data) => WalletsRow(data);
}

class WalletsRow extends SupabaseDataRow {
  WalletsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => WalletsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get stripeAccountId => getField<String>('stripe_account_id');
  set stripeAccountId(String? value) =>
      setField<String>('stripe_account_id', value);

  double get balance {
    final v = data['balance'];
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  set balance(double value) => setField<double>('balance', value);

  /// ZIP 128 — valor contestado / recovery (não levantável)
  double get heldBalance {
    final v = data['held_balance'];
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  set heldBalance(double value) => setField<double>('held_balance', value);

  double get recoveryDebt {
    final v = data['recovery_debt'];
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  String get riskStatus =>
      (getField<String>('risk_status') ?? 'clear').trim();

  String? get riskHoldReason => getField<String>('risk_hold_reason');

  /// ZIP 166 — espelho Connect (account.updated)
  bool? get stripeConnectDetailsSubmitted {
    final v = data['stripe_connect_details_submitted'];
    if (v is bool) return v;
    return null;
  }

  String? get stripeConnectTransfersStatus =>
      getField<String>('stripe_connect_transfers_status')?.trim();

  bool? get stripeConnectPayoutsEnabled {
    final v = data['stripe_connect_payouts_enabled'];
    if (v is bool) return v;
    return null;
  }

  DateTime? get stripeConnectSyncedAt =>
      getField<DateTime>('stripe_connect_synced_at');

  /// Pronto para receber Transfer se KYC submetido e transfers active.
  bool get connectReadyForPayout {
    final hasAccount =
        (stripeAccountId ?? '').trim().isNotEmpty;
    if (!hasAccount) return false;
    final transfers = (stripeConnectTransfersStatus ?? '').toLowerCase();
    if (transfers == 'active') return true;
    // Sem sync ainda: conta existe — Edge valida no levantamento.
    if (transfers.isEmpty && stripeConnectDetailsSubmitted == true) {
      return true;
    }
    return false;
  }

  /// Saldo levantável = balance − held
  double get availableBalance {
    final a = balance - heldBalance;
    return a < 0 ? 0.0 : a;
  }

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);
}
