"""Contexto da live para resolução de comentários ambíguos."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class LiveItemContext:
    live_item_id: str
    ref_code: str
    ref_norm: str
    title: str
    is_active: bool
    public_slot: int
    catalog_ordinal: int
    quantity: int
    variant: str | None = None


@dataclass
class LiveContext:
    live_id: str
    live_title: str
    live_status: str
    active_item_id: str | None
    items: list[LiveItemContext] = field(default_factory=list)

    @classmethod
    def from_api(cls, data: dict) -> LiveContext:
        items = []
        for it in data.get("items") or []:
            items.append(
                LiveItemContext(
                    live_item_id=str(it.get("live_item_id", "")),
                    ref_code=str(it.get("ref_code") or ""),
                    ref_norm=str(it.get("ref_norm") or ""),
                    title=str(it.get("title") or ""),
                    is_active=bool(it.get("is_active")),
                    public_slot=int(it.get("public_slot") or it.get("catalog_ordinal") or 0),
                    catalog_ordinal=int(it.get("catalog_ordinal") or 0),
                    quantity=int(it.get("quantity") or 1),
                    variant=it.get("variant"),
                )
            )
        return cls(
            live_id=str(data.get("live_id", "")),
            live_title=str(data.get("live_title", "")),
            live_status=str(data.get("live_status", "")),
            active_item_id=data.get("active_item_id"),
            items=items,
        )

    @property
    def active_item(self) -> LiveItemContext | None:
        if self.active_item_id:
            for it in self.items:
                if it.live_item_id == self.active_item_id:
                    return it
        for it in self.items:
            if it.is_active:
                return it
        return None

    def find_by_ref_norm(self, ref_norm: str) -> list[LiveItemContext]:
        target = ref_norm.upper().replace(" ", "")

        def core(value: str) -> str:
            v = value.upper().replace(" ", "")
            return v[3:] if v.startswith("REF") else v

        exact = [it for it in self.items if it.ref_norm == target]
        if exact:
            return exact
        c = core(target)
        return [it for it in self.items if core(it.ref_norm) == c]

    def find_by_ref_display(self, ref: str) -> list[LiveItemContext]:
        ref_l = ref.strip().lower()
        return [it for it in self.items if it.ref_code.strip().lower() == ref_l]

    def find_by_slot(self, slot: int) -> list[LiveItemContext]:
        return [
            it for it in self.items
            if it.public_slot == slot or it.catalog_ordinal == slot
        ]

    def find_by_title_hint(self, hint: str) -> list[LiveItemContext]:
        h = hint.strip().lower()
        if len(h) < 3:
            return []
        return [it for it in self.items if h in it.title.lower()]
