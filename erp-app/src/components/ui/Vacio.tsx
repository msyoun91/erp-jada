import type { LucideIcon } from "lucide-react";

// El estado vacío de una pantalla (design system §8): ícono, título y qué hacer. Sin "use client" a
// propósito: así un server component también le pasa el ícono. "Sin resultados" usa `SearchX`.
// Una sección vacía dentro de una ficha no es esto: es `.empty-state-sm`, una línea.
export function Vacio({
  icono: Icono,
  titulo,
  color = "text-text-tertiary",
  accion,
  children,
}: {
  icono: LucideIcon;
  titulo: string;
  // Misión y Equipo: verde si no queda nada, ámbar si lo que queda espera.
  color?: string;
  accion?: React.ReactNode;
  children?: React.ReactNode;
}) {
  return (
    <div className="empty-state">
      <Icono size={30} strokeWidth={1.5} className={`mx-auto mb-3 ${color}`} />
      <p className="t-h3 text-text-secondary">{titulo}</p>
      {children && <p className="t-body-m mt-1">{children}</p>}
      {accion && <div className="mt-4">{accion}</div>}
    </div>
  );
}
