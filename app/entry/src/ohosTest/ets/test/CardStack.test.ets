import { describe, expect, it } from '@ohos/hypium';
import { CardStackLayout } from '../../../main/ets/components/CardStackLayout';

export default function cardStackTest() {
  describe('CardStack', () => {
    const deck = new CardStackLayout(570, 51, [174, 174, 219, 174, 174, 174, 174], 716);

    it('keeps the previous card behind the moving card throughout a turn', 0, () => {
      for (const progress of [0.25, 0.5, 0.75]) {
        const at = deck.locate(deck.offsetAt(1, 0, progress));
        const backTop = deck.paintTop(0, at);
        const frontTop = deck.paintTop(1, at);
        const backBottom = backTop + deck.paintHeight(0, at);
        const frontBottom = frontTop + deck.paintHeight(1, at);
        expect(backTop < frontTop && frontTop < backBottom).assertTrue();
        expect(backBottom < frontBottom).assertTrue();
      }
    });

    it('preserves every exposed layer while the final pair lifts and returns', 0, () => {
      const rest = deck.locate(deck.limit);
      const pushed = deck.dragBy(deck.limit, 80);
      const lifted = deck.locate(pushed);
      expect(lifted.endLift > 0 && lifted.endLift < 80).assertTrue();
      const slots = deck.visibleSlots(rest);
      expect(slots.length > 2).assertTrue();
      expect(deck.visibleSlots(lifted).join(',')).assertEqual(slots.join(','));
      for (const slot of slots) {
        expect(deck.paintTop(slot, lifted)).assertEqual(deck.paintTop(slot, rest));
        expect(deck.paintHeight(slot, lifted)).assertEqual(deck.paintHeight(slot, rest));
      }
      expect(deck.release(pushed, deck.limit, 0)).assertEqual(deck.limit);
    });
  });
}
