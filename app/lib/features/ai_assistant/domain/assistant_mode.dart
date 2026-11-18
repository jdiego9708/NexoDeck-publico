/// En que modo esta el asistente ahora mismo.
///
/// `createActions` es el de siempre: un borrador aceptado solo se guarda si
/// el usuario lo confirma en el editor, nunca corre nada. `liveExecution`
/// ofrece ademas correrlo ya, con confirmacion en el chat.
///
/// Cambiar de modo reinicia la conversacion (`AiChatView._reset`): mezclar
/// una charla que asumia "esto se guarda" con una que asume "esto se corre"
/// confundiria mas de lo que ahorra.
enum AssistantMode { createActions, liveExecution }
