import Foundation

@testable import DitGiff

/// Lean NDJSON slices derived from real Claude Code spike captures.
/// Kept as Swift string constants so the synchronized test target picks them up
/// (loose `.ndjson` files are ignored by the bundle).
enum ClaudeNDJSONFixtures {
    /// From `spike/A-baseline.ndjson`: text deltas, a duplicate assistant text block, success result.
    static let baselineSuccess = """
    {"type":"system","subtype":"init"}
    {"type":"system","subtype":"status"}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Este repositório"}}}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" é uma pequena utilidade em Swift (`Calculator.swift`) com funções para validar idade, c"}}}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"umprimentar por nome e somar uma lista de valores."}}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Este repositório é uma pequena utilidade em Swift (`Calculator.swift`) com funções para validar idade, cumprimentar por nome e somar uma lista de valores."}]}}
    {"type":"result","subtype":"success","is_error":false,"result":"Este repositório é uma pequena utilidade em Swift (`Calculator.swift`) com funções para validar idade, cumprimentar por nome e somar uma lista de valores."}
    """

    /// From `spike/B-tools.ndjson`: a Bash tool_use then text deltas and success.
    static let toolsThenText = """
    {"type":"system","subtype":"init"}
    {"type":"system","subtype":"status"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01215Z94GBWh8cdTEygpmsmn","name":"Bash","input":{"command":"git diff main...feature"}}]}}
    {"type":"system","subtype":"status"}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"O"}}}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" limite de idade válida foi alterado de \\"18 ou mais\\" (`>=`) para \\"ma"}}}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ior que 18\\" (`>`), excluindo agora quem tem exatamente 18 anos."}}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"O limite de idade válida foi alterado de \\"18 ou mais\\" (`>=`) para \\"maior que 18\\" (`>`), excluindo agora quem tem exatamente 18 anos."}]}}
    {"type":"result","subtype":"success","is_error":false,"result":"O limite de idade válida foi alterado de \\"18 ou mais\\" (`>=`) para \\"maior que 18\\" (`>`), excluindo agora quem tem exatamente 18 anos."}
    """

    /// From `spike/E-network.ndjson`: enough `api_retry` rows to trip the second-retry cut-off.
    static let networkRetries = """
    {"type":"system","subtype":"init"}
    {"type":"system","subtype":"status"}
    {"type":"system","subtype":"api_retry","attempt":1,"max_retries":10,"error":"unknown"}
    {"type":"system","subtype":"api_retry","attempt":2,"max_retries":10,"error":"unknown"}
    {"type":"system","subtype":"api_retry","attempt":3,"max_retries":10,"error":"unknown"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"API Error: Unable to connect to API (ConnectionRefused)"}]}}
    {"type":"result","subtype":"error","is_error":true,"result":"API Error: Unable to connect to API (ConnectionRefused)"}
    """

    static let resultError = """
    {"type":"system","subtype":"init"}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}}
    {"type":"result","subtype":"error","is_error":true,"result":"API Error: Unable to connect to API (ConnectionRefused)"}
    """

    static let missingResult = """
    {"type":"system","subtype":"init"}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"truncated answer"}}}
    """

    /// Valid deltas with a garbage line in the middle — the call must still finish.
    static let invalidJSONInTheMiddle = """
    {"type":"system","subtype":"init"}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"before"}}}
    this is not json
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" after"}}}
    {"type":"result","subtype":"success","is_error":false,"result":"before after"}
    """

    static func streamEvents(from ndjson: String, exitCode: Int32 = 0) -> [CommandStreamEvent] {
        var events = ndjson
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { CommandStreamEvent.standardOutputLine($0) }
        events.append(.exited(code: exitCode))
        return events
    }
}
