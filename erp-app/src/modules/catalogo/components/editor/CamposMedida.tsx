"use client";

import { Fragment, useState, type ReactNode } from "react";
import type { InsumoBasico } from "../../types";

type CampoMedida = "medida" | "ancho" | "alto" | "area";

// La unidad dice qué medida hace falta: eso aparece solo, y lo opcional se agrega a pedido. Lo que ya tiene un valor se
// ve mientras la unidad lo use: lo que no, se oculta y la base lo borra al guardar. Sin insumo no hay unidad y se ve todo
// lo cargado. La base lo vuelve a revisar al enviar.
export function CamposMedida({
  usados,
  conValor,
  campo,
}: {
  usados: InsumoBasico[];
  conValor: (c: CampoMedida) => boolean;
  campo: (c: CampoMedida, label: string) => ReactNode;
}) {
  const [pedidos, setPedidos] = useState<CampoMedida[]>([]);
  const enMm = usados.some((i) => i.unidad === "mm");
  const enU = usados.some((i) => i.unidad === "u" && i.tipo !== "servicio");
  const m2 = usados.some((i) => i.unidad === "m2" && i.tipo !== "servicio");
  const m2Servicio = usados.some((i) => i.unidad === "m2" && i.tipo === "servicio");
  const usaMedida = usados.length === 0 || usados.some((i) => i.unidad !== "m2");
  const usaArea = usados.length === 0 || usados.some((i) => i.unidad === "m2");

  const grupos: {
    campos: [CampoMedida, string][];
    aplica: boolean;
    necesario: boolean;
    aPedido: boolean;
    pedir: string;
  }[] = [
    {
      aplica: usaMedida,
      campos: [
        [
          "medida",
          enU ? "Medida de corte (mm, opcional: se cobra la cantidad)" : "Medida (mm)",
        ],
      ],
      necesario: enMm,
      aPedido: enU,
      pedir: "Medida de corte",
    },
    {
      aplica: usaArea,
      campos: [
        ["ancho", "Ancho (mm)"],
        ["alto", "Alto (mm)"],
      ],
      necesario: m2,
      aPedido: m2Servicio,
      pedir: "Ancho y alto (en vez del área)",
    },
    {
      aplica: usaArea,
      campos: [["area", m2 ? "Área (mm², solo si no es un rectángulo)" : "Área (mm²)"]],
      necesario: m2Servicio,
      aPedido: m2,
      pedir: "Área (si no es un rectángulo)",
    },
  ];

  return grupos.map((g) => {
    if (!g.aplica) return null;
    const nombres = g.campos.map(([c]) => c);
    if (g.necesario || nombres.some((c) => pedidos.includes(c) || conValor(c))) {
      return g.campos.map(([c, label]) => <Fragment key={c}>{campo(c, label)}</Fragment>);
    }
    if (!g.aPedido) return null;
    return (
      <button
        key={g.pedir}
        type="button"
        className="tap-target t-caption self-start text-text-brand"
        onClick={() => setPedidos((p) => [...p, ...nombres])}
      >
        + {g.pedir}
      </button>
    );
  });
}
