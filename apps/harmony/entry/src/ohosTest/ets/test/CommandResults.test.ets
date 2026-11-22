import { describe, expect, it } from '@ohos/hypium';
import {
  CommandCandidate, CommandEntry, CommandGroup, CommandPage, CommandResults, CommandRow, CommandTarget, CommandVerb,
  GROUP_LIMIT, GroupedRows
} from '../../../main/ets/app/CommandResults';
import { ProxyMode } from '../../../main/ets/engine/Model';

/* J-3 指令结果分组：组顺序、动词、每组 5 行、key 唯一、词首匹配、高亮移动、回车目标（对齐 Android CommandResultsTest）。 */

function nodeEntries(n: number): CommandEntry[] {
  const out: CommandEntry[] = [];
  for (let i = 0; i < n; i++) {
    out.push(new CommandEntry('n' + i, 'JP', CommandTarget.nodes('n', i)));
  }
  return out;
}

export default function commandResultsTest(): void {
  describe('J-3 command results', () => {
    it('groups ordered and empty groups hidden', 0, () => {
      const rows = CommandResults.rows([
        new CommandEntry('rule', '', CommandTarget.rule('a.com')),
        new CommandEntry('Nodes', '', CommandTarget.page(CommandPage.NODES)),
        new CommandEntry('Global', '', CommandTarget.mode(ProxyMode.GLOBAL))
      ]);
      const gs: GroupedRows[] = CommandResults.groups(rows);
      expect(gs.map((g: GroupedRows) => g.group).join(',')).assertEqual(
        [CommandGroup.COMMAND, CommandGroup.SETTINGS, CommandGroup.RULE_TEST].join(','));
    });

    it('verbs per target kind', 0, () => {
      expect(CommandTarget.mode(ProxyMode.RULE).verb).assertEqual(CommandVerb.APPLY);
      expect(CommandTarget.toggle(true).verb).assertEqual(CommandVerb.APPLY);
      expect(CommandTarget.scene('s').verb).assertEqual(CommandVerb.OPEN);
      expect(CommandTarget.page(CommandPage.LOGS).verb).assertEqual(CommandVerb.OPEN);
      expect(CommandTarget.rule('x').verb).assertEqual(CommandVerb.TEST);
    });

    it('five rows per group until expanded', 0, () => {
      const g = CommandResults.groups(CommandResults.rows(nodeEntries(8)))[0];
      expect(CommandResults.shown(g, []).length).assertEqual(GROUP_LIMIT);
      expect(CommandResults.shown(g, [CommandGroup.NODE]).length).assertEqual(8);
    });

    it('row keys unique even for duplicates', 0, () => {
      const e = new CommandEntry('Same', '', CommandTarget.scene('s'));
      const rows: CommandRow[] = CommandResults.rows([e, e, e]);
      expect(new Set<string>(rows.map((r: CommandRow) => r.key)).size).assertEqual(3);
    });

    it('commands match word prefix of 2+ chars', 0, () => {
      const c = new CommandCandidate('Global', '', CommandTarget.mode(ProxyMode.GLOBAL), [], true);
      expect(CommandResults.matches('g', c)).assertFalse();
      expect(CommandResults.matches('gl', c)).assertTrue();
      expect(CommandResults.matches('GLOBAL', c)).assertTrue();
      expect(CommandResults.matches('obal', c)).assertFalse();
      expect(CommandResults.matches('  ', c)).assertFalse();
    });

    it('highlight moves without wrapping', 0, () => {
      const ks = ['a', 'b', 'c'];
      expect(CommandResults.moveHighlight(undefined, ks, 1, true)).assertEqual('a');
      expect(CommandResults.moveHighlight(undefined, ks, 1, false)).assertEqual('b');
      expect(CommandResults.moveHighlight('a', ks, -1, true)).assertUndefined();
      expect(CommandResults.moveHighlight('a', ks, -1, false)).assertEqual('a');
      expect(CommandResults.moveHighlight('c', ks, 1, true)).assertEqual('c');
    });

    it('enter runs highlighted, else preview, else first row', 0, () => {
      const gs = CommandResults.groups(CommandResults.rows(nodeEntries(3)));
      const keys = CommandResults.visibleRows(gs, []).map((r: CommandRow) => r.key);
      expect(CommandResults.enterRow(gs, [], keys[2], true)?.key).assertEqual(keys[2]);
      expect(CommandResults.enterRow(gs, [], undefined, true)).assertUndefined();
      expect(CommandResults.enterRow(gs, [], undefined, false)?.key).assertEqual(keys[0]);
      expect(CommandResults.defaultKey(gs, undefined, false)).assertEqual(keys[0]);
      expect(CommandResults.defaultKey(gs, undefined, true)).assertUndefined();
    });
  });
}
