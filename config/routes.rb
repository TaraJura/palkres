Rails.application.routes.draw do
  # Auth (generated)
  resource  :session
  resources :passwords, param: :token

  # Health
  get "up" => "rails/health#show", as: :rails_health_check

  # Storefront
  root "storefront/home#show"
  get  "hledat", to: "storefront/search#show", as: :search
  get  "kategorie/*path", to: "storefront/categories#show", as: :category, format: false
  get  "produkt/:slug",   to: "storefront/products#show",   as: :product

  # Cart + checkout
  resource  :kosik, controller: "storefront/cart", only: [:show] do
    post "pridat/:product_id", action: :add,    as: :add
    patch "polozka/:id",       action: :update, as: :update
    delete "polozka/:id",      action: :remove, as: :remove
  end

  namespace :storefront, path: "" do
    resource :checkout, path: "pokladna", only: [:show, :create]
  end

  # Public order-confirmation / status page (token-protected — works for guests too)
  get "objednavka/:number", to: "storefront/order_confirmations#show",
      as: :order_confirmation

  # Account area
  namespace :account, path: "uctu" do
    resources :orders, only: [:index, :show]
    resource  :profile, only: [:show, :update]
  end

  # Admin
  namespace :admin do
    root to: "dashboard#show"
    resources :products, only: [:index, :show, :update]
    resources :orders,   only: [:index, :show, :update]
    resources :sync_runs, only: [:index, :show] do
      collection { post :run_now }
    end
  end
end
