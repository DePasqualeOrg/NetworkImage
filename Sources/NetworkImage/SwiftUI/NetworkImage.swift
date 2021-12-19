import Combine
import CombineSchedulers
import SwiftUI

/// A view that displays an image located at a given URL.
///
/// A network image downloads and displays an image from a given URL; the download is asynchronous,
/// and the result is cached both in disk and memory.
///
/// You create a network image, in its simplest form, by providing the image URL.
///
///     NetworkImage(url: URL(string: "https://picsum.photos/id/237/300/200"))
///       .frame(width: 300, height: 200)
///
/// To manipulate the loaded image, use the `content` parameter.
///
///     NetworkImage(url: URL(string: "https://picsum.photos/id/237/300/200")) { image in
///       image.resizable().scaledToFill()
///     }
///     .frame(width: 150, height: 150)
///     .clipped()
///
/// The view displays a standard placeholder that fills the available space until the image loads. You can
/// specify a custom placeholder by using the `placeholder` parameter.
///
///     NetworkImage(url: URL(string: "https://picsum.photos/id/237/300/200")) { image in
///       image.resizable().scaledToFill()
///     } placeholder: {
///       Color.yellow // Shown while the image is loaded or an error occurs
///     }
///     .frame(width: 150, height: 150)
///     .clipped()
///
/// It is also possible to specify a custom fallback placeholder that the view will display if there is an
/// error or the URL is `nil`.
///
///     NetworkImage(url: URL(string: "https://picsum.photos/id/237/300/200")) { image in
///       image.resizable().scaledToFill()
///     } placeholder: {
///       ProgressView() // Shown while the image is loaded
///     } fallback: {
///       Image(systemName: "photo") // Shown when an error occurs or the URL is nil
///     }
///     .frame(width: 150, height: 150)
///     .clipped()
///     .background(Color.yellow)
///
public struct NetworkImage<Content>: View where Content: View {
  private enum ViewState: Equatable {
    case empty
    case success(URL, Image)
    case failure

    var image: Image? {
      guard case .success(_, let image) = self else {
        return nil
      }
      return image
    }

    var url: URL? {
      guard case .success(let url, _) = self else {
        return nil
      }
      return url
    }
  }

  @Environment(\.networkImageLoader) private var imageLoader
  @State private var viewState = ViewState.empty

  private var url: URL?
  private var scale: CGFloat
  private var transaction: Transaction
  private var content: (ViewState) -> Content

  private var viewStatePublisher: AnyPublisher<ViewState, Never> {
    switch url {
    case .some(let url) where url == viewState.url:
      // Avoid loading the same image again after the layout phase
      return Empty().eraseToAnyPublisher()
    case .some(let url):
      return imageLoader.image(for: url, scale: scale)
        .map { .success(url, .init(platformImage: $0)) }
        .replaceError(with: .failure)
        .receive(on: UIScheduler.shared)
        .eraseToAnyPublisher()
    case .none:
      return Just(.failure).eraseToAnyPublisher()
    }
  }

  /// Loads and displays an image from the specified URL using
  /// a default placeholder until the image loads.
  ///
  /// - Parameters:
  ///   - url: The URL of the image to display.
  ///   - scale: The scale to use for the image. The default is `1`.
  @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  public init(url: URL?, scale: CGFloat = 1) where Content == RedactedImage<Image> {
    self.init(url: url, scale: scale, transaction: .init(), content: { $0 })
  }

  /// Loads and displays a modifiable image from the specified URL using a
  /// default placeholder until the image loads.
  ///
  /// - Parameters:
  ///   - url: The URL where the image is located.
  ///   - scale: The scale to use for the image. The default is `1`.
  ///   - transaction: The transaction to use when the state changes.
  ///   - content: A closure that takes the loaded image as an input, and
  ///     returns the view to show. You can return the image directly, or
  ///     modify it as needed before returning it.
  @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  public init<I>(
    url: URL?,
    scale: CGFloat = 1,
    transaction: Transaction = .init(),
    @ViewBuilder content: @escaping (Image) -> I
  ) where Content == RedactedImage<I>, I: View {
    self.init(
      url: url,
      scale: scale,
      transaction: transaction,
      content: { viewState in
        RedactedImage(image: viewState.image, content: content)
      }
    )
  }

  /// Loads and displays a modifiable image from the specified URL using a
  /// custom placeholder until the image loads.
  ///
  /// - Parameters:
  ///   - url: The URL where the image is located.
  ///   - scale: The scale to use for the image. The default is `1`.
  ///   - transaction: The transaction to use when the state changes.
  ///   - content: A closure that takes the loaded image as an input, and
  ///     returns the view to show. You can return the image directly, or
  ///     modify it as needed before returning it.
  ///   - placeholder: A closure that returns the view to display while the image is loading.
  public init<P, I>(
    url: URL?,
    scale: CGFloat = 1,
    transaction: Transaction = .init(),
    @ViewBuilder content: @escaping (Image) -> I,
    @ViewBuilder placeholder: @escaping () -> P
  ) where Content == _ConditionalContent<P, I>, P: View, I: View {
    self.init(
      url: url,
      scale: scale,
      transaction: transaction,
      content: { viewState in
        switch viewState {
        case .empty, .failure:
          placeholder()
        case .success(_, let image):
          content(image)
        }
      }
    )
  }

  /// Loads and displays a modifiable image from the specified URL using a custom placeholder
  /// until the image loads and a custom fallback if the image fails to load or the URL is `nil`.
  ///
  /// - Parameters:
  ///   - url: The URL where the image is located.
  ///   - scale: The scale to use for the image. The default is `1`.
  ///   - transaction: The transaction to use when the state changes.
  ///   - content: A closure that takes the loaded image as an input, and
  ///     returns the view to show. You can return the image directly, or
  ///     modify it as needed before returning it.
  ///   - placeholder: A closure that returns the view to display while the image is loading.
  ///   - fallback: A closure that returns the view to display when the URL is `nil` or an error has occurred.
  public init<P, I, F>(
    url: URL?,
    scale: CGFloat = 1,
    transaction: Transaction = .init(),
    @ViewBuilder content: @escaping (Image) -> I,
    @ViewBuilder placeholder: @escaping () -> P,
    @ViewBuilder fallback: @escaping () -> F
  ) where Content == _ConditionalContent<_ConditionalContent<P, I>, F>, P: View, I: View, F: View {
    self.init(
      url: url,
      scale: scale,
      transaction: transaction,
      content: { viewState in
        switch viewState {
        case .empty:
          placeholder()
        case .success(_, let image):
          content(image)
        case .failure:
          fallback()
        }
      }
    )
  }

  private init(
    url: URL?,
    scale: CGFloat,
    transaction: Transaction,
    @ViewBuilder content: @escaping (ViewState) -> Content
  ) {
    self.url = url
    self.scale = scale
    self.transaction = transaction
    self.content = content
  }

  public var body: some View {
    content(self.viewState)
      .onReceive(viewStatePublisher) { viewState in
        withTransaction(self.transaction) {
          self.viewState = viewState
        }
      }
  }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public struct RedactedImage<Content>: View where Content: View {
  var image: Image?
  var content: (Image) -> Content

  public var body: some View {
    if let image = self.image {
      content(image)
    } else {
      Image(platformImage: .init()).resizable()
        .redacted(reason: .placeholder)
    }
  }
}

extension Image {
  init(platformImage: PlatformImage) {
    #if os(iOS) || os(tvOS) || os(watchOS)
      self.init(uiImage: platformImage)
    #elseif os(macOS)
      self.init(nsImage: platformImage)
    #endif
  }
}

extension View {
  /// Sets the image loader for network images within this view.
  public func networkImageLoader(_ networkImageLoader: NetworkImageLoader) -> some View {
    environment(\.networkImageLoader, networkImageLoader)
  }
}

extension EnvironmentValues {
  public var networkImageLoader: NetworkImageLoader {
    get { self[NetworkImageLoaderKey.self] }
    set { self[NetworkImageLoaderKey.self] = newValue }
  }
}

private struct NetworkImageLoaderKey: EnvironmentKey {
  static let defaultValue: NetworkImageLoader = .shared
}
