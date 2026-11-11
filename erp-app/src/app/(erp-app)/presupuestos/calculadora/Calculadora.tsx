"use client";

import type { ComponentProps } from "react";
import { QuienPicker } from "@/modules/contactos/components/QuienPicker";
import { AltaObraPanel } from "@/modules/obras/components/ObraFormPanel";
import type { NuevaObraSlot } from "@/modules/presupuestos/components/AltaPresupuestoPanel";
import { CalculadoraVenta } from "@/modules/presupuestos/components/CalculadoraVenta";

// Composición (GUIDE_ENTES §2.7): *+ Nueva obra* abre encima el alta de Obras, con el "¿Quién?" de Contactos, y vuelve al
// panel con la obra elegida (decisiones/presupuestos.md → *Pantallas*).
const NuevaObra: NuevaObraSlot = ({ onCreada, onClose }) => (
  <AltaObraPanel Quien={QuienPicker} onCreada={onCreada} onClose={onClose} />
);

export function Calculadora({
  creaObras,
  ...props
}: Omit<ComponentProps<typeof CalculadoraVenta>, "NuevaObra"> & { creaObras: boolean }) {
  return <CalculadoraVenta {...props} NuevaObra={creaObras ? NuevaObra : undefined} />;
}
