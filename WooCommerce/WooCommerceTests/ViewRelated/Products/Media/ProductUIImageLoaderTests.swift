import Photos
import XCTest
@testable import WooCommerce
@testable import Yosemite

final class ProductUIImageLoaderTests: XCTestCase {
    private let testImage = UIImage.productPlaceholderImage

    private let imageURL = URL(string: "https://woo.com/fun")!
    private let imageURLStringWithSpecialChars = "https://woo.com/тест-图像"

    private var imageService: ImageService!

    private let mockProductImageID: Int64 = 134

    override func setUp() {
        super.setUp()

        let mockCache = MockImageCache(name: "Testing")
        let imagesMapping = [imageURL.absoluteString: testImage,
                             imageURLStringWithSpecialChars.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!: testImage]
        let mockDownloader = MockImageDownloader(imagesByKey: imagesMapping)
        imageService = DefaultImageService(imageCache: mockCache, imageDownloader: mockDownloader)
    }

    override func tearDown() {
        imageService = nil
        super.tearDown()
    }

    func testRequestingImageWithRemoteProductImage() async throws {
        let mockPHAssetImageLoader = MockPHAssetImageLoader(imagesByAsset: [:])
        let imageLoader = DefaultProductUIImageLoader(imageService: imageService, phAssetImageLoaderProvider: { mockPHAssetImageLoader })
        let productImage = ProductImage(imageID: mockProductImageID,
                                        dateCreated: Date(),
                                        dateModified: Date(),
                                        src: imageURL.absoluteString,
                                        name: "woo",
                                        alt: nil)

        let image = try await imageLoader.requestImage(productImage: productImage)
        XCTAssertEqual(image, self.testImage)
    }

    func testRequestingImageWithRemoteProductImageFromURLWithSpecialChars() async throws {
        let mockPHAssetImageLoader = MockPHAssetImageLoader(imagesByAsset: [:])
        let imageLoader = DefaultProductUIImageLoader(imageService: imageService, phAssetImageLoaderProvider: { mockPHAssetImageLoader })
        let productImage = ProductImage(imageID: mockProductImageID,
                                        dateCreated: Date(),
                                        dateModified: Date(),
                                        src: imageURLStringWithSpecialChars,
                                        name: "woo",
                                        alt: nil)

        let image = try await imageLoader.requestImage(productImage: productImage)
        XCTAssertEqual(image, self.testImage)
    }

    func test_request_image_throws_error_if_product_image_has_invalid_url() async throws {
        // Given
        let mockPHAssetImageLoader = MockPHAssetImageLoader(imagesByAsset: [:])
        let mockImageService = MockImageService()
        mockImageService.whenRetrieveImageFromCache(thenReturn: nil)
        mockImageService.whenDownloadImage(thenReturn: UIImage.checkmark)
        let imageLoader = DefaultProductUIImageLoader(imageService: mockImageService,
                                                      phAssetImageLoaderProvider: { mockPHAssetImageLoader })
        let productImage = ProductImage(imageID: mockProductImageID,
                                        dateCreated: Date(),
                                        dateModified: Date(),
                                        src: "invalid_url",
                                        name: "woo",
                                        alt: nil)

        // When
        do {
            _ = try await imageLoader.requestImage(productImage: productImage)
        } catch {
            // Then
            let error = try XCTUnwrap(error as? DefaultProductUIImageLoader.ImageLoaderError)
            XCTAssertEqual(error, .invalidURL)
        }
    }

    func test_request_image_caches_remote_image() async throws {
        // Given
        let mockPHAssetImageLoader = MockPHAssetImageLoader(imagesByAsset: [:])
        let mockImageService = MockImageService()
        mockImageService.whenRetrieveImageFromCache(thenReturn: nil)
        mockImageService.whenDownloadImage(thenReturn: UIImage.checkmark)
        let imageLoader = DefaultProductUIImageLoader(imageService: mockImageService,
                                                      phAssetImageLoaderProvider: { mockPHAssetImageLoader })
        let productImage = ProductImage(imageID: mockProductImageID,
                                        dateCreated: Date(),
                                        dateModified: Date(),
                                        src: imageURL.absoluteString,
                                        name: "woo",
                                        alt: nil)

        // When
        let image = try await imageLoader.requestImage(productImage: productImage)

        // Then
        XCTAssertTrue(mockImageService.downloadImageCalled)
        XCTAssertTrue(mockImageService.shouldCacheImageValue)
    }

    func test_request_image_retrieves_from_cache_if_available() async throws {
        // Given
        let mockPHAssetImageLoader = MockPHAssetImageLoader(imagesByAsset: [:])
        let mockImageService = MockImageService()
        mockImageService.whenRetrieveImageFromCache(thenReturn: UIImage.checkmark)
        mockImageService.whenDownloadImage(thenReturn: UIImage.checkmark)
        let imageLoader = DefaultProductUIImageLoader(imageService: mockImageService,
                                                      phAssetImageLoaderProvider: { mockPHAssetImageLoader })
        let productImage = ProductImage(imageID: mockProductImageID,
                                        dateCreated: Date(),
                                        dateModified: Date(),
                                        src: imageURL.absoluteString,
                                        name: "woo",
                                        alt: nil)

        // When
        let image = try await imageLoader.requestImage(productImage: productImage)

        // Then
        XCTAssertFalse(mockImageService.downloadImageCalled)
        XCTAssertTrue(mockImageService.retrieveImageFromCacheCalled)
    }

    func test_request_image_throws_error_if_image_cannot_be_loaded() async throws {
        // Given
        let mockPHAssetImageLoader = MockPHAssetImageLoader(imagesByAsset: [:])
        let mockImageService = MockImageService()
        mockImageService.whenRetrieveImageFromCache(thenReturn: nil)
        mockImageService.whenDownloadImage(thenThrow: ImageServiceError.other(error: MockError()))
        let imageLoader = DefaultProductUIImageLoader(imageService: mockImageService,
                                                      phAssetImageLoaderProvider: { mockPHAssetImageLoader })
        let productImage = ProductImage(imageID: mockProductImageID,
                                        dateCreated: Date(),
                                        dateModified: Date(),
                                        src: imageURL.absoluteString,
                                        name: "woo",
                                        alt: nil)

        // When
        do {
            _ = try await imageLoader.requestImage(productImage: productImage)
        } catch {
            // Then
            let error = try XCTUnwrap(error as? DefaultProductUIImageLoader.ImageLoaderError)
            XCTAssertEqual(error, .unableToLoadImage)
        }
    }

    func testRequestingImageWithPHAsset() {
        let asset = PHAsset()
        let mockPHAssetImageLoader = MockPHAssetImageLoader(imagesByAsset: [asset: testImage])
        let imageLoader = DefaultProductUIImageLoader(imageService: imageService, phAssetImageLoaderProvider: { mockPHAssetImageLoader })

        let expectation = self.expectation(description: "Wait for image request")
        imageLoader.requestImage(asset: asset, targetSize: .zero) { image in
            XCTAssertEqual(image, self.testImage)
            expectation.fulfill()
        }
        waitForExpectations(timeout: Constants.expectationTimeout, handler: nil)
    }
}

private class MockError: Error {}
