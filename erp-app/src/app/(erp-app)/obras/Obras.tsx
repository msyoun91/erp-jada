"use client";

import type { ComponentProps } from "react";
import { QuienPicker } from "@/modules/contactos/components/QuienPicker";
import { ObrasView } from "@/modules/obras/components/ObrasView";

// Composición (GUIDE_ENTES §2.7): el alta de Obras con el "¿Quién?" de
// Contactos. Vive en `app/` porque los módulos no se importan entre sí, y es
// cliente porque un componente no cruza de servidor a cliente como prop.
export function Obras({ puedeCrear, ...props }: Omit<ComponentProps<typeof ObrasView>, "Quien"> & { puedeCrear: boolean }) {
  return <ObrasView {...props} Quien={puedeCrear ? QuienPicker : undefined} />;
}
