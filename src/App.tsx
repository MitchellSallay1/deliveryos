import { lazy, Suspense } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { ProtectedRoute } from '@/components/ProtectedRoute'
import { RequireAccess } from '@/components/RequireAccess'
import { SuperAdminRoute } from '@/components/SuperAdminRoute'
import { PersonaGate } from '@/components/PersonaGate'
import { AuthLayout } from '@/layouts/AuthLayout'
import { DashboardLayout } from '@/layouts/DashboardLayout'
import { RiderLayout } from '@/layouts/RiderLayout'
import { AdminLayout } from '@/layouts/AdminLayout'
import { LoginPage } from '@/pages/login'
import { RegisterLandingPage } from '@/pages/register/index'
import { RegisterCompanyPage } from '@/pages/register/company'
import { RegisterMerchantPage } from '@/pages/register/merchant'
import { RegisterRiderPage } from '@/pages/register/rider'
import { AuthCallbackPage } from '@/pages/auth-callback'
import { SetupPage } from '@/pages/setup'
import { LinkRiderPage } from '@/pages/link-rider'
import { OnboardingGate } from '@/components/OnboardingGate'
import { TrackPage } from '@/pages/track'
import { PrivacyPage, TermsPage } from '@/pages/legal'
import { MarketingLayout } from '@/layouts/MarketingLayout'
import { MarketingRootPage } from '@/pages/marketing/MarketingRootPage'

const FeaturesPage = lazy(() =>
  import('@/pages/marketing/features').then((m) => ({ default: m.FeaturesPage })),
)
const SolutionsPage = lazy(() =>
  import('@/pages/marketing/solutions').then((m) => ({ default: m.SolutionsPage })),
)
const PricingPage = lazy(() =>
  import('@/pages/marketing/pricing').then((m) => ({ default: m.PricingPage })),
)
const AboutPage = lazy(() => import('@/pages/marketing/about').then((m) => ({ default: m.AboutPage })))
const ContactPage = lazy(() =>
  import('@/pages/marketing/contact').then((m) => ({ default: m.ContactPage })),
)
const FaqPage = lazy(() => import('@/pages/marketing/faq').then((m) => ({ default: m.FaqPage })))
const SecurityPage = lazy(() =>
  import('@/pages/marketing/security').then((m) => ({ default: m.SecurityPage })),
)
const StatusPage = lazy(() => import('@/pages/marketing/status').then((m) => ({ default: m.StatusPage })))
const DevelopersPage = lazy(() =>
  import('@/pages/marketing/developers').then((m) => ({ default: m.DevelopersPage })),
)
const PartnersPage = lazy(() =>
  import('@/pages/marketing/developers').then((m) => ({ default: m.PartnersPage })),
)

const DashboardPage = lazy(() =>
  import('@/pages/dashboard/index').then((m) => ({ default: m.DashboardPage })),
)
const DeliveriesPage = lazy(() =>
  import('@/pages/deliveries/index').then((m) => ({ default: m.DeliveriesPage })),
)
const RidersPage = lazy(() =>
  import('@/pages/riders/index').then((m) => ({ default: m.RidersPage })),
)
const CustomersPage = lazy(() =>
  import('@/pages/customers/index').then((m) => ({ default: m.CustomersPage })),
)
const ReportsPage = lazy(() =>
  import('@/pages/reports/index').then((m) => ({ default: m.ReportsPage })),
)
const NotificationsPage = lazy(() =>
  import('@/pages/notifications/index').then((m) => ({ default: m.NotificationsPage })),
)
const SettingsPage = lazy(() =>
  import('@/pages/settings/index').then((m) => ({ default: m.SettingsPage })),
)
const RiderJobsPage = lazy(() =>
  import('@/pages/rider-jobs/index').then((m) => ({ default: m.RiderJobsPage })),
)
const RiderProfilePage = lazy(() =>
  import('@/pages/rider/profile').then((m) => ({ default: m.RiderProfilePage })),
)
const RiderInvitePage = lazy(() =>
  import('@/pages/rider/invite').then((m) => ({ default: m.RiderInvitePage })),
)
const LiveMapPage = lazy(() =>
  import('@/pages/live-map/index').then((m) => ({ default: m.LiveMapPage })),
)
const OperationsHubPage = lazy(() =>
  import('@/pages/operations/index').then((m) => ({ default: m.OperationsHubPage })),
)
const BranchesPage = lazy(() =>
  import('@/pages/operations/branches').then((m) => ({ default: m.BranchesPage })),
)
const FleetPage = lazy(() =>
  import('@/pages/operations/fleet/index').then((m) => ({ default: m.FleetPage })),
)
const VehicleDetailPage = lazy(() =>
  import('@/pages/operations/fleet/detail').then((m) => ({ default: m.VehicleDetailPage })),
)
const WarehousesPage = lazy(() =>
  import('@/pages/operations/warehouses').then((m) => ({ default: m.WarehousesPage })),
)
const InventoryPage = lazy(() =>
  import('@/pages/operations/inventory/index').then((m) => ({ default: m.InventoryPage })),
)
const InventoryMovementsPage = lazy(() =>
  import('@/pages/operations/inventory/movements').then((m) => ({
    default: m.InventoryMovementsPage,
  })),
)
const CashSettlementsPage = lazy(() =>
  import('@/pages/operations/cash-settlements').then((m) => ({ default: m.CashSettlementsPage })),
)
const TeamPage = lazy(() => import('@/pages/team/index').then((m) => ({ default: m.TeamPage })))
const InvitePage = lazy(() => import('@/pages/invite').then((m) => ({ default: m.InvitePage })))
const AdminOverviewPage = lazy(() =>
  import('@/pages/admin/index').then((m) => ({ default: m.AdminOverviewPage })),
)
const AdminCompaniesPage = lazy(() =>
  import('@/pages/admin/companies').then((m) => ({ default: m.AdminCompaniesPage })),
)
const AdminPlansPage = lazy(() =>
  import('@/pages/admin/plans').then((m) => ({ default: m.AdminPlansPage })),
)
const AdminSubscriptionsPage = lazy(() =>
  import('@/pages/admin/subscriptions').then((m) => ({ default: m.AdminSubscriptionsPage })),
)
const AdminInvoicesPage = lazy(() =>
  import('@/pages/admin/invoices').then((m) => ({ default: m.AdminInvoicesPage })),
)
const AdminPaymentsPage = lazy(() =>
  import('@/pages/admin/payments').then((m) => ({ default: m.AdminPaymentsPage })),
)
const AdminAuditPage = lazy(() =>
  import('@/pages/admin/audit').then((m) => ({ default: m.AdminAuditPage })),
)
const AdminMarketplacePage = lazy(() =>
  import('@/pages/admin/marketplace').then((m) => ({ default: m.AdminMarketplacePage })),
)
const AdminCommerceFinancePage = lazy(() =>
  import('@/pages/admin/commerce-finance').then((m) => ({ default: m.AdminCommerceFinancePage })),
)
const AdminCommerceFeeRulesPage = lazy(() =>
  import('@/pages/admin/commerce-fee-rules').then((m) => ({ default: m.AdminCommerceFeeRulesPage })),
)
const AdminWebhooksPage = lazy(() =>
  import('@/pages/admin/webhooks').then((m) => ({ default: m.AdminWebhooksPage })),
)
const AdminSystemStatusPage = lazy(() =>
  import('@/pages/admin/system-status').then((m) => ({ default: m.AdminSystemStatusPage })),
)
const AdminLivePage = lazy(() => import('@/pages/admin/live').then((m) => ({ default: m.AdminLivePage })))
const AdminMapPage = lazy(() => import('@/pages/admin/map').then((m) => ({ default: m.AdminMapPage })))
const AdminDeliveriesPage = lazy(() =>
  import('@/pages/admin/deliveries').then((m) => ({ default: m.AdminDeliveriesPage })),
)
const AdminNetworkPage = lazy(() =>
  import('@/pages/admin/network').then((m) => ({ default: m.AdminNetworkPage })),
)
const AdminRevenuePage = lazy(() =>
  import('@/pages/admin/revenue').then((m) => ({ default: m.AdminRevenuePage })),
)
const AdminCommunicationsPage = lazy(() =>
  import('@/pages/admin/communications').then((m) => ({ default: m.AdminCommunicationsPage })),
)
const AdminMtnIntegrationsPage = lazy(() =>
  import('@/pages/admin/integrations-mtn').then((m) => ({ default: m.AdminMtnIntegrationsPage })),
)
const AdminApiPage = lazy(() => import('@/pages/admin/api').then((m) => ({ default: m.AdminApiPage })))
const AdminSecurityPage = lazy(() =>
  import('@/pages/admin/security').then((m) => ({ default: m.AdminSecurityPage })),
)
const AdminSupportPage = lazy(() =>
  import('@/pages/admin/support').then((m) => ({ default: m.AdminSupportPage })),
)
const AdminAlertsPage = lazy(() => import('@/pages/admin/alerts').then((m) => ({ default: m.AdminAlertsPage })))
const AdminJobsPage = lazy(() =>
  import('@/pages/admin/platform-config').then((m) => ({ default: m.AdminJobsPage })),
)
const AdminConfigurationPage = lazy(() =>
  import('@/pages/admin/platform-config').then((m) => ({ default: m.AdminConfigurationPage })),
)
const AdminCompanyDetailPage = lazy(() =>
  import('@/pages/admin/company-detail').then((m) => ({ default: m.AdminCompanyDetailPage })),
)
const AdminMerchantsPage = lazy(() =>
  import('@/pages/admin/company-directory').then((m) => ({ default: m.AdminMerchantsPage })),
)
const AdminProvidersPage = lazy(() =>
  import('@/pages/admin/company-directory').then((m) => ({ default: m.AdminProvidersPage })),
)
const AdminUsersPage = lazy(() =>
  import('@/pages/admin/users-riders').then((m) => ({ default: m.AdminUsersPage })),
)
const AdminRidersPage = lazy(() =>
  import('@/pages/admin/users-riders').then((m) => ({ default: m.AdminRidersPage })),
)
const MerchantRequestsPage = lazy(() =>
  import('@/pages/merchant/requests').then((m) => ({ default: m.MerchantRequestsPage })),
)
const MarketplaceJobsPage = lazy(() =>
  import('@/pages/marketplace/jobs').then((m) => ({ default: m.MarketplaceJobsPage })),
)
const MarketplaceProvidersPage = lazy(() =>
  import('@/pages/marketplace/providers').then((m) => ({ default: m.MarketplaceProvidersPage })),
)
const MarketplaceSettingsPage = lazy(() =>
  import('@/pages/marketplace/settings').then((m) => ({ default: m.MarketplaceSettingsPage })),
)
const MarketplaceFinancePage = lazy(() =>
  import('@/pages/marketplace/finance').then((m) => ({ default: m.MarketplaceFinancePage })),
)
const BillingPage = lazy(() =>
  import('@/pages/billing/index').then((m) => ({ default: m.BillingPage })),
)
const VendorOverviewPage = lazy(() =>
  import('@/pages/vendor/index').then((m) => ({ default: m.VendorOverviewPage })),
)
const VendorCatalogPage = lazy(() =>
  import('@/pages/vendor/catalog').then((m) => ({ default: m.VendorCatalogPage })),
)
const VendorProductsPage = lazy(() =>
  import('@/pages/vendor/products').then((m) => ({ default: m.VendorProductsPage })),
)
const VendorOrdersPage = lazy(() =>
  import('@/pages/vendor/orders').then((m) => ({ default: m.VendorOrdersPage })),
)
const VendorLocationsPage = lazy(() =>
  import('@/pages/vendor/locations').then((m) => ({ default: m.VendorLocationsPage })),
)
const VendorFinancePage = lazy(() =>
  import('@/pages/vendor/finance').then((m) => ({ default: m.VendorFinancePage })),
)
const VendorSettingsPage = lazy(() =>
  import('@/pages/vendor/settings').then((m) => ({ default: m.VendorSettingsPage })),
)
const AdminVendorsPage = lazy(() =>
  import('@/pages/admin/vendors').then((m) => ({ default: m.AdminVendorsPage })),
)
const StorePage = lazy(() => import('@/pages/store/index').then((m) => ({ default: m.StorePage })))
const StoreCheckoutPage = lazy(() =>
  import('@/pages/store/checkout').then((m) => ({ default: m.StoreCheckoutPage })),
)
const OrderHistoryPage = lazy(() => import('@/pages/orders/index').then((m) => ({ default: m.OrderHistoryPage })))
const OrderDetailPage = lazy(() => import('@/pages/orders/detail').then((m) => ({ default: m.OrderDetailPage })))

function PageFallback() {
  return (
    <div className="flex min-h-[40vh] items-center justify-center text-sm text-[var(--color-muted)]">
      Loading…
    </div>
  )
}

export function AppRoutes() {
  return (
    <Suspense fallback={<PageFallback />}>
      <Routes>
        <Route element={<AuthLayout />}>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/register" element={<RegisterLandingPage />} />
          <Route path="/register/company" element={<RegisterCompanyPage />} />
          <Route path="/register/merchant" element={<RegisterMerchantPage />} />
          <Route path="/register/rider" element={<RegisterRiderPage />} />
          <Route path="/auth/callback" element={<AuthCallbackPage />} />
        </Route>

        <Route path="/track/:code" element={<TrackPage />} />
        <Route path="/invite/:token" element={<InvitePage />} />
        <Route path="/rider/invite/:code" element={<RiderInvitePage />} />

        {/* Commerce customer storefront — public, no dashboard chrome. Phone
            OTP verification (not company login) gates checkout/order pages. */}
        <Route path="/store/:slug" element={<StorePage />} />
        <Route path="/store/:slug/checkout" element={<StoreCheckoutPage />} />
        <Route path="/orders" element={<OrderHistoryPage />} />
        <Route path="/orders/:id" element={<OrderDetailPage />} />

        <Route element={<MarketingLayout />}>
          <Route path="/" element={<MarketingRootPage />} />
          <Route path="/features" element={<FeaturesPage />} />
          <Route path="/solutions" element={<SolutionsPage />} />
          <Route path="/pricing" element={<PricingPage />} />
          <Route path="/about" element={<AboutPage />} />
          <Route path="/contact" element={<ContactPage />} />
          <Route path="/faq" element={<FaqPage />} />
          <Route path="/security" element={<SecurityPage />} />
          <Route path="/terms" element={<TermsPage />} />
          <Route path="/privacy" element={<PrivacyPage />} />
          <Route path="/status" element={<StatusPage />} />
          <Route path="/developers" element={<DevelopersPage />} />
          <Route path="/partners" element={<PartnersPage />} />
        </Route>

        <Route element={<ProtectedRoute />}>
          <Route path="/setup" element={<SetupPage />} />
          <Route path="/link-rider" element={<LinkRiderPage />} />

          <Route element={<PersonaGate />}>
            <Route element={<RiderLayout />}>
              <Route path="/my-jobs" element={<RiderJobsPage />} />
              <Route path="/rider/profile" element={<RiderProfilePage />} />
            </Route>

            <Route element={<OnboardingGate />}>
              <Route element={<RequireAccess pathPermission />}>
                <Route element={<DashboardLayout />}>
                  <Route path="/dashboard" element={<DashboardPage />} />
                  <Route path="/deliveries" element={<DeliveriesPage />} />
                  <Route path="/merchant/requests" element={<MerchantRequestsPage />} />
                  <Route path="/marketplace/jobs" element={<MarketplaceJobsPage />} />
                  <Route path="/marketplace/settings" element={<MarketplaceSettingsPage />} />
                  <Route path="/marketplace/finance" element={<MarketplaceFinancePage />} />
                  <Route path="/marketplace/providers" element={<MarketplaceProvidersPage />} />
                  <Route path="/billing" element={<BillingPage />} />
                  <Route path="/vendor" element={<VendorOverviewPage />} />
                  <Route path="/vendor/catalog" element={<VendorCatalogPage />} />
                  <Route path="/vendor/products" element={<VendorProductsPage />} />
                  <Route path="/vendor/orders" element={<VendorOrdersPage />} />
                  <Route path="/vendor/locations" element={<VendorLocationsPage />} />
                  <Route path="/vendor/finance" element={<VendorFinancePage />} />
                  <Route path="/vendor/settings" element={<VendorSettingsPage />} />
                  <Route path="/live-map" element={<LiveMapPage />} />
                  <Route path="/operations" element={<OperationsHubPage />} />
                  <Route path="/operations/branches" element={<BranchesPage />} />
                  <Route path="/operations/fleet" element={<FleetPage />} />
                  <Route path="/operations/fleet/:id" element={<VehicleDetailPage />} />
                  <Route path="/operations/warehouses" element={<WarehousesPage />} />
                  <Route path="/operations/inventory" element={<InventoryPage />} />
                  <Route path="/operations/inventory/movements" element={<InventoryMovementsPage />} />
                  <Route path="/operations/cash-settlements" element={<CashSettlementsPage />} />
                  <Route path="/riders" element={<RidersPage />} />
                  <Route path="/customers" element={<CustomersPage />} />
                  <Route path="/reports" element={<ReportsPage />} />
                  <Route path="/notifications" element={<NotificationsPage />} />
                  <Route path="/settings" element={<SettingsPage />} />
                  <Route path="/team" element={<TeamPage />} />
                </Route>
              </Route>
            </Route>
          </Route>
        </Route>

        <Route element={<SuperAdminRoute />}>
          <Route element={<AdminLayout />}>
            <Route path="/admin" element={<AdminOverviewPage />} />
            <Route path="/admin/live" element={<AdminLivePage />} />
            <Route path="/admin/alerts" element={<AdminAlertsPage />} />
            <Route path="/admin/companies" element={<AdminCompaniesPage />} />
            <Route path="/admin/companies/:id" element={<AdminCompanyDetailPage />} />
            <Route path="/admin/merchants" element={<AdminMerchantsPage />} />
            <Route path="/admin/providers" element={<AdminProvidersPage />} />
            <Route path="/admin/vendors" element={<AdminVendorsPage />} />
            <Route path="/admin/users" element={<AdminUsersPage />} />
            <Route path="/admin/riders" element={<AdminRidersPage />} />
            <Route path="/admin/deliveries" element={<AdminDeliveriesPage />} />
            <Route path="/admin/map" element={<AdminMapPage />} />
            <Route path="/admin/network" element={<AdminNetworkPage />} />
            <Route path="/admin/revenue" element={<AdminRevenuePage />} />
            <Route path="/admin/plans" element={<AdminPlansPage />} />
            <Route path="/admin/subscriptions" element={<AdminSubscriptionsPage />} />
            <Route path="/admin/invoices" element={<AdminInvoicesPage />} />
            <Route path="/admin/payments" element={<AdminPaymentsPage />} />
            <Route path="/admin/communications" element={<AdminCommunicationsPage />} />
            <Route path="/admin/integrations/mtn" element={<AdminMtnIntegrationsPage />} />
            <Route path="/admin/api" element={<AdminApiPage />} />
            <Route path="/admin/audit" element={<AdminAuditPage />} />
            <Route path="/admin/security" element={<AdminSecurityPage />} />
            <Route path="/admin/marketplace" element={<AdminMarketplacePage />} />
            <Route path="/admin/commerce-finance" element={<AdminCommerceFinancePage />} />
            <Route path="/admin/commerce-fee-rules" element={<AdminCommerceFeeRulesPage />} />
            <Route path="/admin/webhooks" element={<AdminWebhooksPage />} />
            <Route path="/admin/support" element={<AdminSupportPage />} />
            <Route path="/admin/jobs" element={<AdminJobsPage />} />
            <Route path="/admin/configuration" element={<AdminConfigurationPage />} />
            <Route path="/admin/system-status" element={<AdminSystemStatusPage />} />
          </Route>
        </Route>

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Suspense>
  )
}
