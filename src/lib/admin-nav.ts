import type { LucideIcon } from 'lucide-react'
import {
  Activity,
  AlertTriangle,
  Building2,
  CreditCard,
  FileText,
  Gauge,
  Globe,
  Key,
  LayoutDashboard,
  Map,
  MessageSquare,
  Network,
  Package,
  Radio,
  Receipt,
  Shield,
  Store,
  Tags,
  Truck,
  Users,
  Webhook,
  Wrench,
} from 'lucide-react'

export type AdminNavItem = {
  to: string
  label: string
  icon: LucideIcon
  end?: boolean
}

export type AdminNavGroup = {
  id: string
  label: string
  items: AdminNavItem[]
}

export const ADMIN_NAV_GROUPS: AdminNavGroup[] = [
  {
    id: 'overview',
    label: 'Overview',
    items: [
      { to: '/admin', label: 'Command Center', icon: LayoutDashboard, end: true },
      { to: '/admin/live', label: 'Live Activity', icon: Radio },
      { to: '/admin/alerts', label: 'Alerts', icon: AlertTriangle },
      { to: '/admin/system-status', label: 'System Health', icon: Activity },
    ],
  },
  {
    id: 'customers',
    label: 'Customers',
    items: [
      { to: '/admin/companies', label: 'Companies', icon: Building2 },
      { to: '/admin/merchants', label: 'Merchants', icon: Store },
      { to: '/admin/providers', label: 'Logistics Providers', icon: Truck },
      { to: '/admin/vendors', label: 'Vendor Stores', icon: Store },
      { to: '/admin/users', label: 'Users', icon: Users },
      { to: '/admin/riders', label: 'Riders', icon: Users },
    ],
  },
  {
    id: 'operations',
    label: 'Operations',
    items: [
      { to: '/admin/deliveries', label: 'Deliveries', icon: Package },
      { to: '/admin/map', label: 'Network Map', icon: Map },
      { to: '/admin/network', label: 'Network Performance', icon: Gauge },
      { to: '/admin/marketplace', label: 'Marketplace', icon: Network },
    ],
  },
  {
    id: 'finance',
    label: 'Finance',
    items: [
      { to: '/admin/revenue', label: 'Revenue Center', icon: CreditCard },
      { to: '/admin/plans', label: 'Plans & Features', icon: Tags },
      { to: '/admin/subscriptions', label: 'Subscriptions', icon: Receipt },
      { to: '/admin/invoices', label: 'Invoices', icon: FileText },
      { to: '/admin/payments', label: 'Payments', icon: CreditCard },
    ],
  },
  {
    id: 'communications',
    label: 'Communications',
    items: [{ to: '/admin/communications', label: 'Communications', icon: MessageSquare }],
  },
  {
    id: 'developer',
    label: 'Developer Platform',
    items: [
      { to: '/admin/api', label: 'API & Keys', icon: Key },
      { to: '/admin/webhooks', label: 'Webhooks', icon: Webhook },
      { to: '/admin/integrations/mtn', label: 'MTN Integrations', icon: Globe },
    ],
  },
  {
    id: 'risk',
    label: 'Risk & Security',
    items: [
      { to: '/admin/security', label: 'Security Center', icon: Shield },
      { to: '/admin/audit', label: 'Audit Logs', icon: Shield },
    ],
  },
  {
    id: 'platform',
    label: 'Platform',
    items: [
      { to: '/admin/support', label: 'Support', icon: Users },
      { to: '/admin/jobs', label: 'Scheduled Jobs', icon: Wrench },
      { to: '/admin/configuration', label: 'Configuration', icon: Wrench },
    ],
  },
]

export function adminPageTitle(pathname: string): string {
  for (const group of ADMIN_NAV_GROUPS) {
    for (const item of group.items) {
      if (item.end ? pathname === item.to : pathname === item.to || pathname.startsWith(`${item.to}/`)) {
        return item.label
      }
    }
  }
  if (pathname.startsWith('/admin/companies/')) return 'Company 360'
  return 'Platform admin'
}
