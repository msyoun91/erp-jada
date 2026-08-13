import Link from "next/link";
import { UsersRound, type LucideIcon } from "lucide-react";

const ICON_MAP: Record<string, LucideIcon> = {
  usuarios: UsersRound,
};

type Props = {
  titulo: string;
  icono: string;
  href?: string;
  columnas: 1 | 2;
  children: React.ReactNode;
};

export function WidgetCard({ titulo, icono, href, columnas, children }: Props) {
  const Icon = ICON_MAP[icono];

  const content = (
    <div className={`card ${columnas === 2 ? "sm:col-span-2" : ""}`}>
      <div className="mb-3 flex items-center gap-2">
        <Icon size={16} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        <p className="t-label">{titulo}</p>
      </div>
      {children}
    </div>
  );

  return href ? <Link href={href}>{content}</Link> : content;
}
