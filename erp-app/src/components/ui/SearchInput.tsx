"use client";

import { Search } from "lucide-react";

export function SearchInput({
  value,
  onChange,
  placeholder,
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
}) {
  return (
    <div className="relative min-w-[180px] flex-1">
      <Search
        size={14}
        strokeWidth={1.75}
        className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-text-tertiary"
      />
      <input
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        aria-label={placeholder}
        className="input py-1.5 pl-8"
      />
    </div>
  );
}
