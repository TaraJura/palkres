require "open-uri"

class ImageCacherJob < ApplicationJob
  queue_as :low

  def perform(product_id)
    product = Product.find_by(id: product_id)
    return unless product

    product.product_images.where(cached: false).find_each do |img|
      begin
        URI.parse(img.url_big.presence || img.url).open(read_timeout: 30) do |io|
          img.file.attach(io: io, filename: File.basename(URI.parse(img.url).path))
        end
        img.update!(cached: true)
      rescue => e
        Rails.logger.warn("[ImageCacherJob] product=#{product_id} img=#{img.id} #{e.class}: #{e.message}")
      end
    end
  end
end
