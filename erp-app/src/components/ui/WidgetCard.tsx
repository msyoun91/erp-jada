import Link from "next/link";
import { Building2, UsersRound, type LucideIcon } from "lucide-react";

const ICON_MAP: Record<string, LucideIcon> = {
  usuarios: UsersRound,
  obras: Building2,
};

type Props = {
  titulo: string;
  icono: string;
  href?: string;
  columnas: 1 | 2;
  // Un control propio del widget (el período), a la derecha del título.
  accion?: React.ReactNode;
  children: React.ReactNode;
};

export function WidgetCard({ titulo, icono, href, columnas, accion, children }: Props) {
  const Icon = ICON_MAP[icono];

  // `card-link` solo cuando hay href: la sombra al hover es promesa de click.
  const content = (
    <div
      className={`card ${href ? "card-link" : ""} ${columnas === 2 ? "sm:col-span-2" : ""}`}
    >
      <div className="mb-3 flex items-center gap-2">
        <Icon size={16} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        <p className="t-label flex-1">{titulo}</p>
        {accion}
      </div>
      {children}
    </div>
  );

  return href ? <Link href={href}>{content}</Link> : content;
}
