/// Espaçamento vertical padronizado nas listas de chat (mensagens e secções de sistema).
///
/// - [kChatMessageItemSpacing]: entre mensagens de texto consecutivas.
/// - [kChatSystemSectionSpacing]: entre cartões/secções de sistema (reserva, envio, cancelamento, etc.).
const double kChatMessageItemSpacing = 8.0;
const double kChatSystemSectionSpacing = 12.0;

/// Metade do espaçamento — usar em `EdgeInsets.symmetric(vertical: …)` por item da lista.
const double kChatMessageItemSpacingHalf = kChatMessageItemSpacing / 2;
const double kChatSystemSectionSpacingHalf = kChatSystemSectionSpacing / 2;
