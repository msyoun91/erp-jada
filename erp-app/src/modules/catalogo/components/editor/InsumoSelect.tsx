"use client";

import type { UseFormRegisterReturn } from "react-hook-form";
import { UNIDAD } from "../../etiquetas";
import type { InsumoBasico } from "../../types";

export type InsumosPorId = Map<string, InsumoBasico>;

// Insumos y servicios fijos activos, con su unidad: de ella dependen las fórmulas que lleva el material.
// Uno de baja que ya estaba elegido se sigue viendo, marcado: lo frena el envío.
export function InsumoSelect({
  id,
  insumos,
  registro,
  actual,
  value,
  onChange,
  vacio = "Elegí uno",
  extra,
}: {
  id?: string;
  insumos: InsumosPorId;
  registro?: UseFormRegisterReturn;
  // Con `registro`, el elegido al abrir: si está de baja, se sigue viendo.
  actual?: string | null;
  value?: string;
  onChange?: (v: string) => void;
  vacio?: string;
  extra?: React.ReactNode;
}) {
  const lista = [...insumos.values()];
  const grupo = (tipo: InsumoBasico["tipo"]) =>
    lista
      .filter((i) => i.tipo === tipo && (i.activo || i.id === (value ?? actual)))
      .map((i) => (
        <option key={i.id} value={i.id}>
          {i.nombre} ({UNIDAD[i.unidad]}){i.activo ? "" : " · de baja"}
        </option>
      ));

  return (
    <select
      id={id}
      className="input"
      {...(registro ?? {
        value: value ?? "",
        onChange: (e: React.ChangeEvent<HTMLSelectElement>) => onChange?.(e.target.value),
      })}
    >
      <option value="">{vacio}</option>
      {extra}
      <optgroup label="Insumos">{grupo("insumo")}</optgroup>
      <optgroup label="Servicios fijos">{grupo("servicio")}</optgroup>
    </select>
  );
}
