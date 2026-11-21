import { describe, expect, it } from '@ohos/hypium';
import { CommandParser, CommandSpan, CommandTok, ParsedCommand } from '../../../main/ets/engine/CommandParser';
import { COMMAND_PARSE_V1 } from './fixtures/Fixtures';
import { CommandParseV1, FxCmdCase, FxCmdRegion, FxCmdToken } from './FixtureTypes';

/* 契约 §15.b：command-parse-v1 逐条对拍（与 node 检查 ets-check/test.mjs、tscheck/commandtest.mjs 同一组断言）。 */

class GotToken {
  start: number;
  len: number;
  kind: string;
  text: string;

  constructor(start: number, len: number, kind: string, text: string) {
    this.start = start;
    this.len = len;
    this.kind = kind;
    this.text = text;
  }
}

class GotCase {
  input: string;
  service: string | null;
  scope: string | null;
  region: FxCmdRegion | null;
  action: string | null;
  tokens: GotToken[];

  constructor(input: string, p: ParsedCommand) {
    this.input = input;
    this.service = p.service !== undefined ? p.service.name : null;
    this.scope = p.service !== undefined ? p.service.scope : null;
    this.region = p.region !== undefined ? { name: p.region.name, code: p.region.code } as FxCmdRegion : null;
    this.action = p.act !== undefined ? p.act.toString() : null;
    this.tokens = p.spans.map((s: CommandSpan) => new GotToken(s.start, s.length, s.kind.toString(),
      input.substring(s.start, s.start + s.length)));
  }
}

function expected(c: FxCmdCase): string {
  return JSON.stringify({
    input: c.input, service: c.service, scope: c.scope, region: c.region, action: c.action,
    tokens: c.tokens.map((t: FxCmdToken) => new GotToken(t.start, t.len, t.kind, t.text))
  } as FxCmdCase);
}

export default function commandParseTest(): void {
  describe('CommandParser', () => {
    it('matches contract/fixtures/command-parse-v1.json', 0, () => {
      const fx: CommandParseV1 = JSON.parse(COMMAND_PARSE_V1) as CommandParseV1;
      expect(fx.cases.length > 0).assertTrue();
      for (const c of fx.cases) {
        const got = JSON.stringify(new GotCase(c.input, CommandParser.parse(c.input)));
        const want = expected(c);
        if (got !== want) {
          console.error('MISMATCH ' + c.input + ' ' + got + ' != ' + want);
        }
        expect(got).assertEqual(want);
      }
    });

    it('short latin codes only match whole words', 0, () => {
      expect(CommandParser.parse('status').region === undefined).assertTrue();
      const p = CommandParser.parse('Claude us');
      expect(p.region !== undefined && p.region.code === 'US').assertTrue();
    });

    it('hasChips only with a service or an action', 0, () => {
      expect(CommandParser.parse('香港').hasChips).assertFalse();
      expect(CommandParser.parse('github 直连').hasChips).assertTrue();
      expect(CommandParser.parse('4K').spans[0].kind === CommandTok.ACTION).assertTrue();
    });
  });
}
